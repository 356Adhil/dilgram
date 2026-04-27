const { GoogleGenerativeAI } = require("@google/generative-ai");

class GeminiService {
  constructor() {
    if (!process.env.GEMINI_API_KEY) {
      console.warn("GEMINI_API_KEY not set — AI features disabled");
      this.enabled = false;
      return;
    }
    this.genAI = new GoogleGenerativeAI(process.env.GEMINI_API_KEY);
    this.model = this.genAI.getGenerativeModel({ model: "gemini-2.0-flash" });
    this.enabled = true;
  }

  /**
   * Analyze a memory's image and generate title, description, tags, mood
   * @param {string} imageUrl - Cloudinary image URL
   * @returns {Object} { title, description, tags, mood }
   */
  async analyzeImage(imageUrl) {
    if (!this.enabled) throw new Error("AI features not configured");

    const response = await fetch(imageUrl);
    const arrayBuffer = await response.arrayBuffer();
    const base64 = Buffer.from(arrayBuffer).toString("base64");
    const mimeType = response.headers.get("content-type") || "image/jpeg";

    const result = await this.model.generateContent([
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

    const text = result.response.text().trim();
    // Strip markdown code blocks if present
    const cleaned = text
      .replace(/^```(?:json)?\n?/i, "")
      .replace(/\n?```$/i, "")
      .trim();
    return JSON.parse(cleaned);
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
      const response = await fetch(url);
      const arrayBuffer = await response.arrayBuffer();
      const base64 = Buffer.from(arrayBuffer).toString("base64");
      const mimeType = response.headers.get("content-type") || "image/jpeg";
      images.push({ inlineData: { mimeType, data: base64 } });
    }

    const result = await this.model.generateContent([
      ...images,
      {
        text: `These images are from a personal memory collection. Respond with ONLY a JSON object (no markdown, no code blocks):
{
  "story": "A warm, nostalgic 2-3 sentence narrative connecting these images as a memory story",
  "theme": "A short theme/category for this collection (e.g., 'Weekend Adventure', 'Cozy Evening', 'Nature Walk')"
}`,
      },
    ]);

    const text = result.response.text().trim();
    const cleaned = text
      .replace(/^```(?:json)?\n?/i, "")
      .replace(/\n?```$/i, "")
      .trim();
    return JSON.parse(cleaned);
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

    const result = await this.model.generateContent([
      {
        text: `You are a friendly AI companion for a personal memories app called Dilgram. The user has these memories:

${context}

User message: ${message}

Respond naturally and helpfully. Keep responses concise (2-4 sentences). If they ask about their memories, reference the ones listed. Be warm and personal.`,
      },
    ]);

    return result.response.text().trim();
  }
}

module.exports = new GeminiService();
