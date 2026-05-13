import { GoogleGenAI, Type } from "@google/genai";

// MARK: - Types

export interface InspirationItem {
  title: string;
  description: string;
  style: string;
  imageBase64: string;
  imageMimeType: string;
  imageGenPrompt: string;
}

export interface InspirationResult {
  inspirations: InspirationItem[];
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

// MARK: - Generate Inspirations

export async function generateInspirations(
  base64Image: string,
  mimeType: string,
  language: string,
  apiKey: string
): Promise<InspirationResult> {
  const ai = createAIClient(apiKey);

  // Determine language instruction
  const languageInstruction =
    language === "zh-Hans" || language === "zh-Hant" || language.startsWith("zh")
      ? "请用中文回复所有文字内容（title, description, style）。"
      : "Please respond all text content (title, description, style) in English.";

  // Step 1: Analyze image and get inspiration suggestions
  const analysisResponse = await ai.models.generateContent({
    model: "gemini-3-flash-preview",
    contents: {
      parts: [
        {
          inlineData: {
            data: base64Image,
            mimeType: mimeType,
          },
        },
        {
          text: `Analyze the main subject and the environment in this photo. Suggest 3 creative photography inspirations that specifically focus on different POSES, BODY LANGUAGE, and CAMERA ANGLES for this subject in this EXACT SAME LOCATION.

${languageInstruction}

Guidelines:
1. The environment/background must stay the same.
2. Focus on how the person (or subject) can move, look, or interact with the space differently.
3. Suggest different camera heights (low angle, eye level, etc.) or distances (close-up vs full body).

For each inspiration, provide:
1. A catchy title (e.g., 'The Low-Angle Power Pose').
2. A description explaining the pose/angle technique.
3. A one-word style descriptor (e.g. Dynamic, Elegant, Candid).
4. An image generation prompt in English that describes the pose/angle change while keeping the background identical.`,
        },
      ],
    },
    config: {
      responseMimeType: "application/json",
      responseSchema: {
        type: Type.OBJECT,
        properties: {
          inspirations: {
            type: Type.ARRAY,
            items: {
              type: Type.OBJECT,
              properties: {
                title: { type: Type.STRING },
                description: { type: Type.STRING },
                style: { type: Type.STRING },
                imageGenPrompt: {
                  type: Type.STRING,
                  description: "English prompt for image generation",
                },
              },
              required: ["title", "description", "style", "imageGenPrompt"],
            },
          },
        },
        required: ["inspirations"],
      },
    },
  });

  const analysisText = analysisResponse.text;
  if (!analysisText) throw new Error("No response from AI analysis");

  const analysis = JSON.parse(analysisText) as {
    inspirations: Array<{
      title: string;
      description: string;
      style: string;
      imageGenPrompt: string;
    }>;
  };

  // Step 2: Prepare inspirations without images (Lazy loading will handle image generation)
  const inspirations = analysis.inspirations.map((inspiration) => {
    return {
      title: inspiration.title,
      description: inspiration.description,
      style: inspiration.style,
      imageBase64: "",
      imageMimeType: "",
      imageGenPrompt: inspiration.imageGenPrompt,
    };
  });

  return { inspirations };
}

export async function generateInspirationImage(
  base64Image: string,
  mimeType: string,
  imageGenPrompt: string,
  apiKey: string
): Promise<{ imageBase64: string; imageMimeType: string }> {
  const ai = createAIClient(apiKey);
  
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
            text: `STRICT INSTRUCTION: Keep the BACKGROUND, ENVIRONMENT, and LOCATION of this photo exactly the same. 
Modify ONLY the subject's pose and the camera angle as follows: ${imageGenPrompt}.
The subject's identity and clothing should remain consistent.
Result must look like a professional photography alternative shot of the same person in the same spot.`,
          },
        ],
      },
      config: {
        responseModalities: ["image", "text"],
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
    console.error("Image generation failed:", error);
  }

  // If image generation failed, return empty
  return {
    imageBase64: "",
    imageMimeType: "",
  };
}
