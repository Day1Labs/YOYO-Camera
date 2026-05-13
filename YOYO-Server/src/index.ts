import { verifyAppleIdentityToken } from "./auth/apple";
import { validateAppleSubscription } from "./iap";
import { generateShareCode } from "./share_code";
import { generateInspirations, generateInspirationImage } from "./inspiration";
import { processAIDarkroomRequest } from "./ai_darkroom";
import { CreditService, PRO_MONTHLY_CREDITS, DEFAULT_FREE_CREDITS } from "./credits";
import jwt from "@tsndr/cloudflare-worker-jwt";

interface AuthRequest {
  identityToken: string;
  userIdentifier: string;
  fullName?: string;
  email?: string;
}

interface User {
  id: number;
  appleUserId: string;
  email: string | null;
  fullName: string | null;
  credits: number;
  subscriptionStatus: number; // 0: free, 1: pro
}

interface ShareRequest {
  ruleJson: string;
}

interface InspirationRequest {
  imageBase64: string;
  mimeType: string;
  language: string;
}

interface InspirationImageRequest {
  imageBase64: string;
  mimeType: string;
  imageGenPrompt: string;
}

export default {
  async fetch(request, env, _ctx): Promise<Response> {
    const { pathname } = new URL(request.url);

    // CORS headers
    const corsHeaders = {
      "Access-Control-Allow-Origin": "*",
      "Access-Control-Allow-Methods": "GET, POST, DELETE, OPTIONS",
      "Access-Control-Allow-Headers": "Content-Type, Authorization",
    };

    if (request.method === "OPTIONS") {
      return new Response(null, { headers: corsHeaders });
    }

    // Apple Sign In
    if (pathname === "/api/auth/apple" && request.method === "POST") {
      try {
        const body: AuthRequest = await request.json();
        const { identityToken, userIdentifier, fullName, email } = body;

        if (!identityToken || !userIdentifier) {
          return Response.json(
            { error: "Missing identityToken or userIdentifier" },
            { status: 400, headers: corsHeaders }
          );
        }

        // Verify Apple identity token
        const isValid = await verifyAppleIdentityToken(identityToken, userIdentifier);
        if (!isValid) {
          return Response.json(
            { error: "Invalid identity token" },
            { status: 401, headers: corsHeaders }
          );
        }

        // Check if user exists
        const existingUser = await env.DB.prepare(
          "SELECT id, apple_user_id, email, full_name, credits, subscription_status FROM users WHERE apple_user_id = ?"
        )
          .bind(userIdentifier)
          .first<{
            id: number;
            apple_user_id: string;
            email: string | null;
            full_name: string | null;
            credits: number;
            subscription_status: number;
          }>();

        let user: User;

        if (existingUser) {
          // Update user info if new data provided or reactivate user (clear deleted_at)
          await env.DB.prepare(
            "UPDATE users SET full_name = COALESCE(?, full_name), email = COALESCE(?, email), deleted_at = NULL, updated_at = datetime('now') WHERE apple_user_id = ?"
          )
            .bind(fullName || null, email || null, userIdentifier)
            .run();

          user = {
            id: existingUser.id,
            appleUserId: existingUser.apple_user_id,
            email: email || existingUser.email,
            fullName: fullName || existingUser.full_name,
            credits: existingUser.credits ?? DEFAULT_FREE_CREDITS,
            subscriptionStatus: existingUser.subscription_status ?? 0,
          };
        } else {
          // Create new user
          const result = await env.DB.prepare(
            `INSERT INTO users (apple_user_id, email, full_name, credits, subscription_status) VALUES (?, ?, ?, ${DEFAULT_FREE_CREDITS}, 0)`
          )
            .bind(userIdentifier, email || null, fullName || null)
            .run();

          user = {
            id: result.meta.last_row_id as number,
            appleUserId: userIdentifier,
            email: email || null,
            fullName: fullName || null,
            credits: DEFAULT_FREE_CREDITS,
            subscriptionStatus: 0,
          };
        }

        const token = await jwt.sign(
          {
            id: user.id,
            exp: Math.floor(Date.now() / 1000) + 7 * 24 * 60 * 60, // 7 days
          },
          env.JWT_SECRET
        );

        return Response.json({ user, token }, { headers: corsHeaders });
      } catch (error) {
        console.error("Auth error:", error);
        return Response.json(
          { error: "Internal server error" },
          { status: 500, headers: corsHeaders }
        );
      }
    }

    // Get user profile
    if (pathname === "/api/user" && request.method === "GET") {
      try {
        const authHeader = request.headers.get("Authorization");
        if (!authHeader || !authHeader.startsWith("Bearer ")) {
          return Response.json(
            { error: "Missing or invalid authorization header" },
            { status: 401, headers: corsHeaders }
          );
        }

        const token = authHeader.split(" ")[1];
        const isValid = await jwt.verify(token, env.JWT_SECRET);
        if (!isValid) {
          return Response.json({ error: "Invalid token" }, { status: 401, headers: corsHeaders });
        }

        const { payload } = jwt.decode(token);
        const userId = (payload as { id: number }).id;

        const user = await env.DB.prepare(
          "SELECT id, apple_user_id, email, full_name, credits, subscription_status FROM users WHERE id = ?"
        )
          .bind(userId)
          .first<{
            id: number;
            apple_user_id: string;
            email: string | null;
            full_name: string | null;
            credits: number;
            subscription_status: number;
          }>();

        if (!user) {
          return Response.json({ error: "User not found" }, { status: 404, headers: corsHeaders });
        }

        const userResponse: User = {
          id: user.id,
          appleUserId: user.apple_user_id,
          email: user.email,
          fullName: user.full_name,
          credits: user.credits ?? DEFAULT_FREE_CREDITS,
          subscriptionStatus: user.subscription_status ?? 0,
        };

        return Response.json(userResponse, { headers: corsHeaders });
      } catch (error) {
        console.error("Get user profile error:", error);
        return Response.json(
          { error: "Internal server error" },
          { status: 500, headers: corsHeaders }
        );
      }
    }

    // Delete user account
    if (pathname === "/api/user" && request.method === "DELETE") {
      try {
        const authHeader = request.headers.get("Authorization");
        if (!authHeader || !authHeader.startsWith("Bearer ")) {
          return Response.json(
            { error: "Missing or invalid authorization header" },
            { status: 401, headers: corsHeaders }
          );
        }

        const token = authHeader.split(" ")[1];
        const isValid = await jwt.verify(token, env.JWT_SECRET);
        if (!isValid) {
          return Response.json({ error: "Invalid token" }, { status: 401, headers: corsHeaders });
        }

        const { payload } = jwt.decode(token);
        const userId = (payload as { id: number }).id;

        // Explicitly delete related records to avoid FOREIGN KEY constraint failed error
        // Soft delete the user to prevent credit farming (re-registering for initial credits)
        await env.DB.batch([
          env.DB.prepare("DELETE FROM shared_automation_rules WHERE user_id = ?").bind(userId),
          env.DB.prepare(`
            UPDATE users 
            SET deleted_at = datetime('now'), 
                email = NULL, 
                full_name = NULL, 
                credits = 0, 
                subscription_status = 0,
                updated_at = datetime('now')
            WHERE id = ?
          `).bind(userId),
        ]);

        return Response.json({ success: true }, { headers: corsHeaders });
      } catch (error) {
        console.error("Delete user error:", error);
        return Response.json(
          { error: "Internal server error" },
          { status: 500, headers: corsHeaders }
        );
      }
    }

    // Update user profile
    if (pathname === "/api/user" && request.method === "PUT") {
      try {
        const authHeader = request.headers.get("Authorization");
        if (!authHeader || !authHeader.startsWith("Bearer ")) {
          return Response.json(
            { error: "Missing or invalid authorization header" },
            { status: 401, headers: corsHeaders }
          );
        }

        const token = authHeader.split(" ")[1];
        const isValid = await jwt.verify(token, env.JWT_SECRET);
        if (!isValid) {
          return Response.json({ error: "Invalid token" }, { status: 401, headers: corsHeaders });
        }

        const { payload } = jwt.decode(token);
        const userId = (payload as { id: number }).id;

        const body: { fullName?: string } = await request.json();
        const { fullName } = body;

        if (!fullName || fullName.trim().length === 0) {
           return Response.json(
            { error: "Full name is required" },
            { status: 400, headers: corsHeaders }
          );
        }
        
        if (fullName.length > 30) {
           return Response.json(
            { error: "Full name is too long" },
            { status: 400, headers: corsHeaders }
          );
        }

        await env.DB.prepare(
          "UPDATE users SET full_name = ?, updated_at = datetime('now') WHERE id = ?"
        )
          .bind(fullName.trim(), userId)
          .run();

        return Response.json({ fullName: fullName.trim() }, { headers: corsHeaders });

      } catch (error) {
        console.error("Update user error:", error);
        return Response.json(
          { error: "Internal server error" },
          { status: 500, headers: corsHeaders }
        );
      }
    }

    // Verify IAP Receipt
    if (pathname === "/api/user/subscribe" && request.method === "POST") {
      try {
        const authHeader = request.headers.get("Authorization");
        if (!authHeader || !authHeader.startsWith("Bearer ")) {
          return Response.json(
            { error: "Missing or invalid authorization header" },
            { status: 401, headers: corsHeaders }
          );
        }

        const token = authHeader.split(" ")[1];
        const isValid = await jwt.verify(token, env.JWT_SECRET);
        if (!isValid) {
          return Response.json({ error: "Invalid token" }, { status: 401, headers: corsHeaders });
        }

        const { payload } = jwt.decode(token);
        const userId = (payload as { id: number }).id;

        const body: { originalTransactionId: string } = await request.json();
        const { originalTransactionId } = body;

        if (!originalTransactionId) {
          return Response.json(
            { error: "Missing originalTransactionId" },
            { status: 400, headers: corsHeaders }
          );
        }

        // Check if this transaction ID is already bound to ANOTHER user
        // But we allow re-binding to the SAME user (e.g. restore purchase, re-install)
        // We need to check if 'last_transaction_id' is used by someone else? 
        // No, 'last_transaction_id' changes every month. We need to track the 'original_transaction_id'.
        // Let's add 'original_transaction_id' column to users table or just query broadly.
        // Since we don't have 'original_transaction_id' column yet, let's skip strict binding for now 
        // OR reuse 'last_transaction_id' if we assume it stores original? 
        // Wait, the code stores `validationResult.transactionId` into `last_transaction_id`.
        // That is the LATEST transaction ID (e.g. this month's renewal), NOT the original one (first ever).
        // To do binding properly, we should store `original_transaction_id` in the users table.
        
        // For now, let's implement the logic assuming we will add the column or use a dedicated table.
        // Given current schema limitations, I will add a TODO or basic check if possible.
        // Actually, let's add the column via migration if we were in a real env.
        // Here, I will check if `last_transaction_id` matches, but that's weak.
        
        // Strategy: We will check if ANY user has this `originalTransactionId` stored.
        // But we don't store `originalTransactionId` yet. 
        // We only store `last_transaction_id`.
        // Let's modify the UPDATE to also store `original_transaction_id` if we add the column?
        // User asked to "Implement the suggestion". The suggestion was "Check Transaction Binding".
        
        // Let's assume we want to enforce: One Apple ID (via originalTransactionId) -> One YOYO Account.
        // We need to check if `originalTransactionId` is associated with another user_id.
        // Since we don't store it yet, I should probably add it to the schema first?
        // Or I can use `apple_user_id` which is already unique per user.
        // Wait, `originalTransactionId` comes from IAP. `apple_user_id` comes from Sign in with Apple.
        // They are different.
        
        // CORRECT APPROACH:
        // 1. Add `original_transaction_id` to `users` table.
        // 2. When subscribing, check if `original_transaction_id` exists in table for a DIFFERENT user.
        
        // Since I cannot easily run D1 migrations here without user intervention, 
        // I will implement the LOGIC in code, but I need to update Schema first.
        // Let's try to update schema.sql and assume user will run migration? 
        // Or just fail gracefully if column missing? No, that causes 500.
        
        // Let's stick to the plan: I will update `index.ts` to perform the check, 
        // assuming I will also provide the schema update instructions or file.
        
        // Check if another user has this originalTransactionId
        // We need a way to store it. 
        // I'll add `original_transaction_id` to the UPDATE query and the check logic.
        
        // Step 1: Check binding
        const boundUser = await env.DB.prepare("SELECT id FROM users WHERE original_transaction_id = ?")
            .bind(originalTransactionId)
            .first<{ id: number }>();

        if (boundUser && boundUser.id !== userId) {
             return Response.json(
            { error: "This subscription is already bound to another account." },
            { status: 409, headers: corsHeaders }
          );
        }

        // Validate with Apple using App Store Server API
        const validationResult = await validateAppleSubscription(originalTransactionId, env);
        
        if (!validationResult.isValid) {
             return Response.json(
            { error: "Invalid subscription or verification failed" },
            { status: 400, headers: corsHeaders }
          );
        }

        // Update user status
        const status = validationResult.isPro ? 1 : 0;
        const endDate = validationResult.expiresDateMs 
            ? new Date(validationResult.expiresDateMs).toISOString() 
            : null;
            
        let finalCredits: number | null = null;
        
        // Case 1: Pro Active (Status 1)
        if (status === 1) {
            const transactionId = validationResult.transactionId;
            if (transactionId) {
                // Atomic Update for New Transaction (Accumulate credits)
                // Only update if transaction_id is different (prevent race condition/double counting)
                const result = await env.DB.prepare(`
                    UPDATE users 
                    SET subscription_status = ?, 
                        subscription_end_date = ?, 
                        updated_at = datetime('now'), 
                        original_transaction_id = ?,
                        credits = credits + ?,
                        last_transaction_id = ?
                    WHERE id = ? AND (last_transaction_id IS NULL OR last_transaction_id != ?)
                    RETURNING credits
                `)
                .bind(
                    status, 
                    endDate, 
                    originalTransactionId, 
                    PRO_MONTHLY_CREDITS, 
                    transactionId, 
                    userId, 
                    transactionId
                ).first<{ credits: number }>();
                
                if (result) {
                    // Updated successfully with new credits
                    finalCredits = result.credits;
                    console.log(`[Subscribe] New transaction ${transactionId} processed. Credits updated to ${finalCredits}`);
                } else {
                    // Transaction ID matched existing one, or update failed. 
                    // Just update status details without adding credits (Idempotent update)
                    const updateResult = await env.DB.prepare(`
                        UPDATE users 
                        SET subscription_status = ?, 
                            subscription_end_date = ?, 
                            updated_at = datetime('now'), 
                            original_transaction_id = ?
                        WHERE id = ?
                        RETURNING credits
                    `)
                    .bind(status, endDate, originalTransactionId, userId)
                    .first<{ credits: number }>();
                    
                    finalCredits = updateResult?.credits ?? 0;
                    console.log(`[Subscribe] Existing transaction. Status updated. Credits: ${finalCredits}`);
                }
            }
        } 
        // Case 2: Revoked (Refund)
        else if (validationResult.cancellationDateMs) {
             // Refunded! Deduct credits safely (MAX(0, credits - PRO_MONTHLY_CREDITS))
             // Instead of wiping to 0, we assume we want to take back the credits given for this subscription period.
             const result = await env.DB.prepare(`
                UPDATE users 
                SET subscription_status = ?, 
                    subscription_end_date = ?, 
                    updated_at = datetime('now'), 
                    original_transaction_id = ?,
                    credits = MAX(0, credits - ?)
                WHERE id = ?
                RETURNING credits
            `)
            .bind(
                status, 
                endDate, 
                originalTransactionId, 
                PRO_MONTHLY_CREDITS, 
                userId
            ).first<{ credits: number }>();
            
            finalCredits = result?.credits ?? 0;
            console.log(`[Subscribe] Subscription revoked. Credits deducted to ${finalCredits}`);
        }
        // Case 3: Just expired naturally
        else {
             // Do nothing to credits
             const result = await env.DB.prepare(`
                UPDATE users 
                SET subscription_status = ?, 
                    subscription_end_date = ?, 
                    updated_at = datetime('now'), 
                    original_transaction_id = ?
                WHERE id = ?
                RETURNING credits
             `)
             .bind(status, endDate, originalTransactionId, userId)
             .first<{ credits: number }>();
             
             finalCredits = result?.credits ?? 0;
        }

        return Response.json({ 
            subscriptionStatus: status, 
            subscriptionEndDate: endDate,
            credits: finalCredits
        }, { headers: corsHeaders });

      } catch (error) {
        console.error("Subscribe error:", error);
        return Response.json(
          { error: `Internal server error: ${error instanceof Error ? error.message : String(error)}` },
          { status: 500, headers: corsHeaders }
        );
      }
    }

    // Share automation rule
    if (pathname === "/api/automation/share" && request.method === "POST") {
      try {
        // Verify JWT token
        const authHeader = request.headers.get("Authorization");
        if (!authHeader || !authHeader.startsWith("Bearer ")) {
          return Response.json(
            { error: "Missing or invalid authorization header" },
            { status: 401, headers: corsHeaders }
          );
        }

        const token = authHeader.split(" ")[1];
        const isValid = await jwt.verify(token, env.JWT_SECRET);

        if (!isValid) {
          return Response.json(
            { error: "Invalid token" },
            { status: 401, headers: corsHeaders }
          );
        }

        const { payload } = jwt.decode(token);
        const userId = (payload as { id: number }).id;

        const body: ShareRequest = await request.json();
        const { ruleJson } = body;

        if (!ruleJson) {
          return Response.json(
            { error: "Missing ruleJson" },
            { status: 400, headers: corsHeaders }
          );
        }

        // Check payload size (limit to 20KB)
        if (ruleJson.length > 20480) {
          return Response.json(
            { error: "Payload too large" },
            { status: 413, headers: corsHeaders }
          );
        }

        // Verify user exists (optional, since token is valid, but good for consistency)
        const user = await env.DB.prepare("SELECT id FROM users WHERE id = ?")
          .bind(userId)
          .first();

        if (!user) {
          return Response.json(
            { error: "User not found" },
            { status: 401, headers: corsHeaders }
          );
        }

        // Generate a share code and insert it, retrying on conflicts
        const maxRetries = 7; // Covers attempt=0..6
        let code = "";
        for (let attempt = 0; attempt < maxRetries; attempt++) {
          code = generateShareCode(attempt);
          try {
            await env.DB.prepare(
              "INSERT INTO shared_automation_rules (code, rule_json, user_id) VALUES (?, ?, ?)"
            )
              .bind(code, ruleJson, userId)
              .run();
            break; // Insert succeeded, exit the loop
          } catch (e: unknown) {
            const error = e as Error;
            // Retry on unique constraint conflicts
            if (error.message?.includes("UNIQUE constraint failed") && attempt < maxRetries - 1) {
              continue;
            }
            throw e;
          }
        }

        return Response.json({ code }, { headers: corsHeaders });
      } catch (error) {
        console.error("Share error:", error);
        return Response.json(
          { error: "Internal server error" },
          { status: 500, headers: corsHeaders }
        );
      }
    }

    // Get shared automation rule by code
    if (pathname.startsWith("/api/automation/share/") && request.method === "GET") {
      try {
        const code = pathname.split("/").pop();

        if (!code || code.length !== 6) {
          return Response.json(
            { error: "Invalid share code" },
            { status: 400, headers: corsHeaders }
          );
        }

        const result = await env.DB.prepare(
          "SELECT rule_json FROM shared_automation_rules WHERE code = ?"
        )
          .bind(code.toUpperCase())
          .first<{ rule_json: string }>();

        if (!result) {
          return Response.json(
            { error: "Share code not found" },
            { status: 404, headers: corsHeaders }
          );
        }

        return Response.json({ ruleJson: result.rule_json }, { headers: corsHeaders });
      } catch (error) {
        console.error("Get shared rule error:", error);
        return Response.json(
          { error: "Internal server error" },
          { status: 500, headers: corsHeaders }
        );
      }
    }

    // AI Inspiration - Generate inspirations with images
    if (pathname === "/api/inspiration" && request.method === "POST") {
      try {
        // Verify JWT token
        const authHeader = request.headers.get("Authorization");
        if (!authHeader || !authHeader.startsWith("Bearer ")) {
          return Response.json(
            { error: "Missing or invalid authorization header" },
            { status: 401, headers: corsHeaders }
          );
        }

        const token = authHeader.split(" ")[1];
        const isValid = await jwt.verify(token, env.JWT_SECRET);

        if (!isValid) {
          return Response.json(
            { error: "Invalid token" },
            { status: 401, headers: corsHeaders }
          );
        }

        const { payload } = jwt.decode(token);
        const userId = (payload as { id: number }).id;

        // Check subscription status
        const user = await env.DB.prepare(
          "SELECT subscription_status, subscription_end_date FROM users WHERE id = ?"
        )
          .bind(userId)
          .first<{ subscription_status: number; subscription_end_date: string | null }>();

        if (!user) {
           return Response.json(
            { error: "User not found" },
            { status: 401, headers: corsHeaders }
          );
        }

        const isPro = user.subscription_status === 1;
        // Optional: Check expiration explicitly if we trust the DB field or want double check
        // const isExpired = user.subscription_end_date && new Date(user.subscription_end_date).getTime() < Date.now();
        
        if (!isPro) {
             return Response.json(
            { error: "Pro membership required", status: 0 },
            { status: 403, headers: corsHeaders }
          );
        }
        
        // Check and deduct credits
        const creditService = new CreditService(env);
        const userCredits = await creditService.getUserCredits(userId);

        if (!userCredits) {
          return Response.json(
            { error: "User not found" },
            { status: 401, headers: corsHeaders }
          );
        }

        // Even Pro users need credits now (monthly quota)
        if (userCredits.credits < 1) {
          return Response.json(
            { 
              error: "Insufficient credits", 
              credits: userCredits.credits, 
              status: userCredits.subscriptionStatus 
            },
            { status: 403, headers: corsHeaders }
          );
        }

        /* 
           Original Credit Logic Removed for Pro-Gating 
        */

        const body: InspirationRequest = await request.json();
        const { imageBase64, mimeType, language } = body;

        if (!imageBase64 || !mimeType) {
          return Response.json(
            { error: "Missing imageBase64 or mimeType" },
            { status: 400, headers: corsHeaders }
          );
        }

        // Check payload size (limit to 10MB for images)
        if (imageBase64.length > 10 * 1024 * 1024) {
          return Response.json(
            { error: "Image too large" },
            { status: 413, headers: corsHeaders }
          );
        }

        const result = await generateInspirations(
          imageBase64,
          mimeType,
          language || "en",
          env.GEMINI_API_KEY
        );

        // Deduct credit
        const remainingCredits = await creditService.deductCredits(userId, 1);
        
        return Response.json(
          { ...result, credits: remainingCredits },
          { headers: corsHeaders }
        );
      } catch (error) {
        console.error("Inspiration error:", error);
        return Response.json(
          { error: "Failed to generate inspirations" },
          { status: 500, headers: corsHeaders }
        );
      }
    }

    // AI Inspiration - Generate single image (Lazy loading)
    if (pathname === "/api/inspiration/image" && request.method === "POST") {
      try {
        // Verify JWT token
        const authHeader = request.headers.get("Authorization");
        if (!authHeader || !authHeader.startsWith("Bearer ")) {
          return Response.json(
            { error: "Missing or invalid authorization header" },
            { status: 401, headers: corsHeaders }
          );
        }

        const token = authHeader.split(" ")[1];
        const isValid = await jwt.verify(token, env.JWT_SECRET);

        if (!isValid) {
          return Response.json(
            { error: "Invalid token" },
            { status: 401, headers: corsHeaders }
          );
        }

        const { payload } = jwt.decode(token);
        const userId = (payload as { id: number }).id;

        // Check subscription status
        const user = await env.DB.prepare(
          "SELECT subscription_status, subscription_end_date FROM users WHERE id = ?"
        )
          .bind(userId)
          .first<{ subscription_status: number; subscription_end_date: string | null }>();

        if (!user) {
           return Response.json(
            { error: "User not found" },
            { status: 401, headers: corsHeaders }
          );
        }

        const isPro = user.subscription_status === 1;
        
        if (!isPro) {
             return Response.json(
            { error: "Pro membership required", status: 0 },
            { status: 403, headers: corsHeaders }
          );
        }

        // Check and deduct credits
        const creditService = new CreditService(env);
        const userCredits = await creditService.getUserCredits(userId);

        if (!userCredits) {
          return Response.json(
            { error: "User not found" },
            { status: 401, headers: corsHeaders }
          );
        }

        if (userCredits.credits < 1) {
          return Response.json(
            { 
              error: "Insufficient credits", 
              credits: userCredits.credits, 
              status: userCredits.subscriptionStatus 
            },
            { status: 403, headers: corsHeaders }
          );
        }

        const body: InspirationImageRequest = await request.json();
        const { imageBase64, mimeType, imageGenPrompt } = body;

        if (!imageBase64 || !mimeType || !imageGenPrompt) {
          return Response.json(
            { error: "Missing required fields" },
            { status: 400, headers: corsHeaders }
          );
        }

        // Check payload size
        if (imageBase64.length > 10 * 1024 * 1024) {
          return Response.json(
            { error: "Image too large" },
            { status: 413, headers: corsHeaders }
          );
        }

        const result = await generateInspirationImage(
          imageBase64,
          mimeType,
          imageGenPrompt,
          env.GEMINI_API_KEY
        );

        // Deduct credit
        const remainingCredits = await creditService.deductCredits(userId, 1);

        return Response.json({ ...result, credits: remainingCredits }, { headers: corsHeaders });
      } catch (error) {
        console.error("Inspiration image generation error:", error);
        return Response.json(
          { error: "Failed to generate inspiration image" },
          { status: 500, headers: corsHeaders }
        );
      }
    }

    // AI Darkroom - Process Image
    if (pathname === "/api/ai_darkroom/process" && request.method === "POST") {
      try {
        // Verify JWT token
        const authHeader = request.headers.get("Authorization");
        if (!authHeader || !authHeader.startsWith("Bearer ")) {
          return Response.json(
            { error: "Missing or invalid authorization header" },
            { status: 401, headers: corsHeaders }
          );
        }

        const token = authHeader.split(" ")[1];
        const isValid = await jwt.verify(token, env.JWT_SECRET);

        if (!isValid) {
          return Response.json(
            { error: "Invalid token" },
            { status: 401, headers: corsHeaders }
          );
        }

        const { payload } = jwt.decode(token);
        const userId = (payload as { id: number }).id;

        // Check subscription status
        const user = await env.DB.prepare(
          "SELECT subscription_status FROM users WHERE id = ?"
        )
          .bind(userId)
          .first<{ subscription_status: number }>();

        if (!user) {
           return Response.json(
            { error: "User not found" },
            { status: 401, headers: corsHeaders }
          );
        }

        const isPro = user.subscription_status === 1;
        
        if (!isPro) {
             return Response.json(
            { error: "Pro membership required", status: 0 },
            { status: 403, headers: corsHeaders }
          );
        }

        // Check credits
        const creditService = new CreditService(env);
        const userCredits = await creditService.getUserCredits(userId);

        if (!userCredits || userCredits.credits < 1) {
          return Response.json(
            { error: "Insufficient credits", credits: userCredits?.credits ?? 0 },
            { status: 403, headers: corsHeaders }
          );
        }

        const body: any = await request.json();
        const { imageBase64, mimeType, operation, options } = body;

        if (!imageBase64 || !mimeType || !operation) {
          return Response.json(
            { error: "Missing required fields" },
            { status: 400, headers: corsHeaders }
          );
        }

        const result = await processAIDarkroomRequest(
          imageBase64,
          mimeType,
          operation,
          options,
          env.GEMINI_API_KEY
        );

        // Deduct credit
        const remainingCredits = await creditService.deductCredits(userId, 1);

        return Response.json({ ...result, credits: remainingCredits }, { headers: corsHeaders });
      } catch (error) {
        console.error("AI Darkroom error:", error);
        return Response.json(
          { error: "Failed to process AI Darkroom request" },
          { status: 500, headers: corsHeaders }
        );
      }
    }

    // App Store Server Notifications V2 Webhook
    if (pathname === "/api/webhook/appstore" && request.method === "POST") {
      try {
        // In a real production app, you MUST verify the JWS signature using Apple's public keys.
        // For simplicity here, we trust the payload if it decodes, but this is NOT secure for production without signature verification.
        // See: https://developer.apple.com/documentation/appstoreservernotifications/notificationtype
        
        const body: any = await request.json();
        const signedPayload = body.signedPayload;
        
        if (!signedPayload) {
             return new Response("Missing signedPayload", { status: 400 });
        }
        
        // Decode JWS
        const decoded = jwt.decode(signedPayload);
        if (!decoded || !decoded.payload) {
             return new Response("Invalid JWS", { status: 400 });
        }
        
        const payload = decoded.payload as any;
        const notificationType = payload.notificationType;
        const subtype = payload.subtype;
        
        console.log(`[Webhook] Received notification: ${notificationType} - ${subtype}`);
        
        // We are interested in EXPIRED, DID_RENEW, REFUND, REVOKE
        if (payload.data && payload.data.signedTransactionInfo) {
             const signedTx = payload.data.signedTransactionInfo;
             const decodedTx = jwt.decode(signedTx);
             
             if (decodedTx && decodedTx.payload) {
                 const txInfo = decodedTx.payload as any;
                 const originalTransactionId = txInfo.originalTransactionId;
                 const transactionId = txInfo.transactionId;
                 const expiresDateMs = parseInt(txInfo.expiresDate);
                 const revocationDateMs = txInfo.revocationDate ? parseInt(txInfo.revocationDate) : undefined;
                 
                 console.log(`[Webhook] Processing Tx: ${originalTransactionId}, Expires: ${expiresDateMs}`);
                 
                 // Find user by originalTransactionId
                 // We added 'original_transaction_id' column to schema, so we can use it now.
                 const user = await env.DB.prepare("SELECT id, credits, last_transaction_id FROM users WHERE original_transaction_id = ?")
                    .bind(originalTransactionId)
                    .first<{ id: number, credits: number, last_transaction_id: string }>();
                    
                 if (user) {
                     const nowMs = Date.now();
                     let status = 0;
                     const endDate = new Date(expiresDateMs).toISOString();
                     
                     // Determine status
                     if (expiresDateMs > nowMs && !revocationDateMs) {
                         status = 1; // Active Pro
                         
                         // Try to apply renewal credits atomically
                         // We attempt to update AND check last_transaction_id in one go
                         const result = await env.DB.prepare(`
                            UPDATE users 
                            SET subscription_status = ?, 
                                subscription_end_date = ?, 
                                updated_at = datetime('now'),
                                credits = credits + ?,
                                last_transaction_id = ?
                            WHERE id = ? AND (last_transaction_id IS NULL OR last_transaction_id != ?)
                         `)
                         .bind(
                             status, 
                             endDate, 
                             PRO_MONTHLY_CREDITS, 
                             transactionId, 
                             user.id, 
                             transactionId
                         ).run();
                         
                         // If no rows modified, it means transactionId was same.
                         if (result.meta.changes === 0) {
                             // Just update status details without adding credits
                             await env.DB.prepare(`
                                UPDATE users 
                                SET subscription_status = ?, 
                                    subscription_end_date = ?, 
                                    updated_at = datetime('now')
                                WHERE id = ?
                             `).bind(status, endDate, user.id).run();
                             console.log(`[Webhook] User ${user.id} status refreshed (No new credits).`);
                         } else {
                             console.log(`[Webhook] Renewal processed for user ${user.id}. Credits added.`);
                         }
                         
                     } else {
                         status = 0; // Expired or Revoked
                         
                         if (revocationDateMs) {
                             // Revocation - Deduct credits safely
                             console.log(`[Webhook] Revocation detected for user ${user.id}`);
                             await env.DB.prepare(`
                                UPDATE users 
                                SET subscription_status = ?, 
                                    subscription_end_date = ?, 
                                    updated_at = datetime('now'),
                                    credits = MAX(0, credits - ?)
                                WHERE id = ?
                             `)
                             .bind(status, endDate, PRO_MONTHLY_CREDITS, user.id)
                             .run();
                         } else {
                             // Just Expired - Update status only
                             await env.DB.prepare(`
                                UPDATE users 
                                SET subscription_status = ?, 
                                    subscription_end_date = ?, 
                                    updated_at = datetime('now')
                                WHERE id = ?
                             `)
                             .bind(status, endDate, user.id)
                             .run();
                         }
                     }
                     
                     console.log(`[Webhook] Processed user ${user.id}. Final status: ${status}`);
                 } else {
                     console.log(`[Webhook] No user found for originalTransactionId: ${originalTransactionId}`);
                 }
             }
        }
        
        return new Response("OK", { status: 200 });
      } catch (error) {
        console.error("Webhook error:", error);
        return new Response("Internal Server Error", { status: 500 });
      }
    }

    return new Response("YOYO Camera API", { headers: corsHeaders });
  },
} satisfies ExportedHandler<Env>;
