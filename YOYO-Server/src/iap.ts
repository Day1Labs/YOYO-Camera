import jwt from "@tsndr/cloudflare-worker-jwt";

export interface IAPResponse {
  isValid: boolean;
  expiresDateMs?: number;
  isPro: boolean;
  transactionId?: string;
  cancellationDateMs?: number;
}

export async function validateAppleSubscription(
  originalTransactionId: string,
  env: Env
): Promise<IAPResponse> {
  const { APP_STORE_KEY_ID, APP_STORE_ISSUER_ID, APP_STORE_BUNDLE_ID, APP_STORE_PRIVATE_KEY } = env;

  if (!APP_STORE_KEY_ID || !APP_STORE_ISSUER_ID || !APP_STORE_BUNDLE_ID || !APP_STORE_PRIVATE_KEY) {
      console.error("Missing App Store Server API configuration");
      // Fallback or Fail: For safety, fail.
      return { isValid: false, isPro: false };
  }
  
  // 1. Generate JWT for Apple API
  const now = Math.floor(Date.now() / 1000);
  
  // Format private key strictly for PKCS#8
  const privateKey = formatPrivateKey(APP_STORE_PRIVATE_KEY);
  
  const token = await jwt.sign({
      iss: APP_STORE_ISSUER_ID,
      iat: now,
      exp: now + 3600,
      aud: "appstoreconnect-v1",
      bid: APP_STORE_BUNDLE_ID
  }, privateKey, {
      algorithm: "ES256",
      header: {
          kid: APP_STORE_KEY_ID,
          typ: "JWT"
      }
  });

  // 2. Call Apple API (Get All Subscription Statuses)
  // https://developer.apple.com/documentation/appstoreserverapi/get_all_subscription_statuses
  
  let response = await fetchSubscriptionStatus(originalTransactionId, token, false);
  
  if (response.status === 404) {
      // Try Sandbox
      response = await fetchSubscriptionStatus(originalTransactionId, token, true);
  }
  
  if (!response.ok) {
      console.error(`App Store API failed: ${response.status}`);
      // Handle 404 meaning no sub found
      return { isValid: false, isPro: false };
  }
  
  const data: any = await response.json();
  
  // 3. Parse Response
  let latestExpiresDateMs = 0;
  let latestTransactionId = "";
  let latestCancellationDateMs: number | undefined;

  // The API returns { data: [ { subscriptionGroupIdentifier: "...", lastTransactions: [...] } ] }
  for (const group of data.data || []) {
      for (const item of group.lastTransactions || []) {
          const signedInfo = item.signedTransactionInfo;
          // Decode JWS payload without verification (trusted channel)
          const decoded = jwt.decode(signedInfo);
          
          if (!decoded || !decoded.payload) continue;
          
          const { payload } = decoded;
          
          const info = payload as any;
          const expiresDate = parseInt(info.expiresDate);
          
          // Find the latest expiration date across all transactions
          if (expiresDate > latestExpiresDateMs) {
              latestExpiresDateMs = expiresDate;
              latestTransactionId = info.transactionId;
              
              if (info.revocationDate) {
                  latestCancellationDateMs = parseInt(info.revocationDate);
              } else {
                  latestCancellationDateMs = undefined;
              }
          }
      }
  }

  const nowMs = Date.now();
  // Check if active: Not expired AND Not cancelled
  const isPro = latestExpiresDateMs > nowMs && !latestCancellationDateMs;
  
  return {
      isValid: true,
      expiresDateMs: latestExpiresDateMs,
      isPro,
      transactionId: latestTransactionId,
      cancellationDateMs: latestCancellationDateMs
  };
}

async function fetchSubscriptionStatus(originalTransactionId: string, token: string, isSandbox: boolean) {
    const baseUrl = isSandbox 
        ? "https://api.storekit-sandbox.itunes.apple.com" 
        : "https://api.storekit.itunes.apple.com";
        
    const url = `${baseUrl}/inApps/v1/subscriptions/${originalTransactionId}`;
    
    return fetch(url, {
        headers: {
            "Authorization": `Bearer ${token}`
        }
    });
}

function formatPrivateKey(key: string): string {
    // 1. Replace literal \n with real newlines
    let cleanKey = key.replace(/\\n/g, '\n');
  
    // 2. Remove headers to get raw body if they exist
    // This handles cases where user might have messy headers or spacing
    if (cleanKey.includes('-----BEGIN PRIVATE KEY-----')) {
      cleanKey = cleanKey
        .replace('-----BEGIN PRIVATE KEY-----', '')
        .replace('-----END PRIVATE KEY-----', '');
    }
  
    // 3. Remove all whitespace (spaces, tabs, newlines) from body
    const body = cleanKey.replace(/\s/g, '');
  
    // 4. Reconstruct standard PEM format
    return `-----BEGIN PRIVATE KEY-----\n${body}\n-----END PRIVATE KEY-----`;
}
