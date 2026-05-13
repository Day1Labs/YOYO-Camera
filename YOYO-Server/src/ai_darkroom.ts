import { GoogleGenAI } from "@google/genai";

// MARK: - Types

export enum AIDarkroomOperation {
  PORTRAIT_ENHANCE = "portrait_enhance",
  ID_PHOTO = "id_photo",
  PROFESSIONAL_PHOTO = "professional_photo",
  SOCIAL_AVATAR = "social_avatar",
  REMOVE_OBJECTS = "remove_objects",
  BLUR_REPAIR = "blur_repair",
  COLOR_GRADING = "color_grading",
  FIX_CLOSED_EYES = "fix_closed_eyes"
}

// MARK: - AI Client Factory

function createAIClient(apiKey: string): GoogleGenAI {
  const accountId = "8a7a6290a9e2e925dd0ccc3b42d865c0";
  const gatewayName = "yoyo";

  return new GoogleGenAI({
    apiKey: apiKey,
    httpOptions: {
      baseUrl: `https://gateway.ai.cloudflare.com/v1/${accountId}/${gatewayName}/google-ai-studio`
    },
  });
}

// MARK: - Process Request

export async function processAIDarkroomRequest(
  base64Image: string,
  mimeType: string,
  operation: string,
  options: any,
  apiKey: string
): Promise<{ imageBase64: string; imageMimeType: string }> {
  const ai = createAIClient(apiKey);
  
  let systemPrompt = "";
  
  switch (operation) {
    case AIDarkroomOperation.PORTRAIT_ENHANCE:
        systemPrompt = "You are a professional photo retoucher. Enhance this portrait with: 1. Smart lighting (brighten face but no overexposure). 2. Retain skin texture while removing blemishes. 3. Enhance eyes. 4. Make hair clearer. 5. Remove fatigue (dark circles) without changing facial structure. Return the enhanced image.";
        break;
    case AIDarkroomOperation.ID_PHOTO:
        systemPrompt = "Convert this photo into a professional ID photo. 1. Clean background (white or blue). 2. Adjust lighting to be even. 3. Center the subject. Return the ID photo.";
        break;
    case AIDarkroomOperation.PROFESSIONAL_PHOTO:
        systemPrompt = "Transform this photo into a high-quality professional/LinkedIn profile photo. Professional clothing, confident expression, appropriate blurry office or studio background.";
        break;
    case AIDarkroomOperation.SOCIAL_AVATAR:
        systemPrompt = "Create a stylized, high-quality social media avatar based on this photo. Artistic, vibrant, and unique, suitable for Instagram/TikTok profile pictures.";
        break;
    case AIDarkroomOperation.REMOVE_OBJECTS:
        systemPrompt = "Identify and remove any passersby, clutter, or distracting objects from the background. Fill the gaps naturally using context aware fill. The main subject should remain unchanged.";
        break;
    case AIDarkroomOperation.BLUR_REPAIR:
        systemPrompt = "Restoration mode: Fix blur, sharpen details, and upscale the image resolution. Make it look crisp and clear.";
        break;
    case AIDarkroomOperation.COLOR_GRADING:
        systemPrompt = "Smart Color Grading: If portrait, prioritize natural and healthy skin tones. If landscape, enhance sky and vegetation separately. If night scene, reduce noise while preserving atmosphere. Apply cinematic color grading.";
        break;
    case AIDarkroomOperation.FIX_CLOSED_EYES:
        systemPrompt = "The user has provided a photo where a person might have their eyes closed or partially closed. Your task is to realistically open their eyes. 1. Detect the face and eyes. 2. Generate natural-looking open eyes that match the person's probable eye color and shape based on facial features. 3. Ensure the gaze direction is natural (usually looking at the camera). 4. Blend seamlessly with the surrounding skin. 5. Keep the rest of the face and image exactly as is. Return the fixed image.";
        break;
    default:
        throw new Error("Unknown operation");
  }

  try {
    const imageResponse = await ai.models.generateContent({
      model: "gemini-2.5-flash-image",
      contents: {
        parts: [
          {
            inlineData: {
              data: base64Image,
              mimeType: mimeType,
            },
          },
          {
            text: systemPrompt,
          },
        ],
      },
      config: {
        responseModalities: ["image"],
      },
    });

    // Extract image from response
    for (const part of imageResponse.candidates?.[0]?.content?.parts || []) {
      if (part.inlineData) {
        return {
          imageBase64: part.inlineData.data || "",
          imageMimeType: part.inlineData.mimeType || "image/png",
        };
      }
    }
  } catch (error) {
    console.error("AI Darkroom processing failed:", error);
    throw error;
  }

  throw new Error("Failed to generate image");
}
