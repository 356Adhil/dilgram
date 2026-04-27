const { GoogleGenerativeAI } = require("@google/generative-ai");

class GeminiService {
  constructor() {
    if (!process.env.GEMINI_API_KEY) {
      console.warn("GEMINI_API_KEY not set — AI features disabled");
      this.enabled = false;
      return;
    }
    this.genAI = new GoogleGenerativeAI(process.env.GEMINI_API_KEY);
    this.model = this.genAI.getGenerativeModel({
      model: process.env.GEMINI_MODEL || "gemini-2.0-flash-lite",
      generationConfig: {
        temperature: 0.7,
        maxOutputTokens: 1024,
      },
    });
    this.enabled = true;
  }

  /**
   * Analyze a memory's image and generate title, description, tags, mood
   * @param {string} imageUrl - Cloudinary image URL
   * @returns {Object} { title, description, tags, mood }
   */
  async analyzeImage(imageUrl) {
    if (!this.enabled) throw new Error("AI features not configured");

    let response;
    try {
      response = await fetch(imageUrl);
    } catch (fetchErr) {
      throw new Error(`Failed to fetch image from URL: ${fetchErr.message}`);
    }

    if (!response.ok) {
      throw new Error(
        `Failed to fetch image: HTTP ${response.status} ${response.statusText}`,
      );
    }

    const arrayBuffer = await response.arrayBuffer();
    const base64 = Buffer.from(arrayBuffer).toString("base64");
    const mimeType = response.headers.get("content-type") || "image/jpeg";

    let result;
    try {
      result = await this.model.generateContent([
        {
          inlineData: {
            mimeType,
            data: base64,
          },
        },
        {
          text: `Analyze this image and respond with ONLY a JSON object (no markdown, no code blocks):
{
  "title": "A short creative title (max 6 words)",
  "description": "A poetic 1-2 sentence description of what's in the image, written as a personal memory caption",
  "tags": ["tag1", "tag2", "tag3", "tag4", "tag5"],
  "mood": "one word mood/emotion this image evokes"
}`,
        },
      ]);
    } catch (aiErr) {
      console.error("Gemini API error (analyzeImage):", aiErr.message);
      if (aiErr.message && aiErr.message.includes("429")) {
        throw new Error(
          "AI quota exceeded. Please try again later or upgrade your plan.",
        );
      }
      throw new Error(`Gemini API error: ${aiErr.message}`);
    }

    const text = result.response.text().trim();
    // Strip markdown code blocks if present
    const cleaned = text
      .replace(/^```(?:json)?\n?/i, "")
      .replace(/\n?```$/i, "")
      .trim();

    try {
      return JSON.parse(cleaned);
    } catch (parseErr) {
      console.error("Failed to parse Gemini response:", text);
      // Return a fallback instead of crashing
      return {
        title: "Untitled Memory",
        description: text.slice(0, 200),
        tags: [],
        mood: "neutral",
      };
    }
  }

  /**
   * Generate a caption for multiple images (memory story)
   * @param {Array<string>} imageUrls - Array of Cloudinary URLs
   * @returns {Object} { story, theme }
   */
  async generateStory(imageUrls) {
    if (!this.enabled) throw new Error("AI features not configured");

    const images = [];
    for (const url of imageUrls.slice(0, 4)) {
      let response;
      try {
        response = await fetch(url);
      } catch (fetchErr) {
        console.error(`Failed to fetch image ${url}:`, fetchErr.message);
        continue;
      }
      if (!response.ok) {
        console.error(`Failed to fetch image ${url}: HTTP ${response.status}`);
        continue;
      }
      const arrayBuffer = await response.arrayBuffer();
      const base64 = Buffer.from(arrayBuffer).toString("base64");
      const mimeType = response.headers.get("content-type") || "image/jpeg";
      images.push({ inlineData: { mimeType, data: base64 } });
    }

    if (images.length === 0) {
      throw new Error("Could not fetch any images for story generation");
    }

    let result;
    try {
      result = await this.model.generateContent([
        ...images,
        {
          text: `These images are from a personal memory collection. Respond with ONLY a JSON object (no markdown, no code blocks):
{
  "story": "A warm, nostalgic 2-3 sentence narrative connecting these images as a memory story",
  "theme": "A short theme/category for this collection (e.g., 'Weekend Adventure', 'Cozy Evening', 'Nature Walk')"
}`,
        },
      ]);
    } catch (aiErr) {
      console.error("Gemini API error (generateStory):", aiErr.message);
      if (aiErr.message && aiErr.message.includes("429")) {
        throw new Error(
          "AI quota exceeded. Please try again later or upgrade your plan.",
        );
      }
      throw new Error(`Gemini API error: ${aiErr.message}`);
    }

    const text = result.response.text().trim();
    const cleaned = text
      .replace(/^```(?:json)?\n?/i, "")
      .replace(/\n?```$/i, "")
      .trim();

    try {
      return JSON.parse(cleaned);
    } catch (parseErr) {
      console.error("Failed to parse Gemini story response:", text);
      return {
        story: text.slice(0, 300),
        theme: "Your Week",
      };
    }
  }

  /**
   * Chat with AI about memories
   * @param {string} message - User message
   * @param {Array} memorySummary - Brief summary of user's memories
   * @returns {string} AI response
   */
  async chat(message, memorySummary) {
    if (!this.enabled) throw new Error("AI features not configured");

    const context = memorySummary
      .map(
        (m) =>
          `- ${m.title || "Untitled"} (${new Date(m.createdAt).toLocaleDateString()}): ${m.mediaCount} media items${m.description ? `, "${m.description}"` : ""}`,
      )
      .join("\n");

    let result;
    try {
      result = await this.model.generateContent([
        {
          text: `You are a friendly AI companion for a personal memories app called Dilgram. The user has these memories:

${context}

User message: ${message}

Respond naturally and helpfully. Keep responses concise (2-4 sentences). If they ask about their memories, reference the ones listed. Be warm and personal.`,
        },
      ]);
    } catch (aiErr) {
      console.error("Gemini API error (chat):", aiErr.message);
      if (aiErr.message && aiErr.message.includes("429")) {
        throw new Error(
          "AI quota exceeded. Please try again later or upgrade your plan.",
        );
      }
      throw new Error(`Gemini API error: ${aiErr.message}`);
    }

    return result.response.text().trim();
  }
}

module.exports = new GeminiService();
