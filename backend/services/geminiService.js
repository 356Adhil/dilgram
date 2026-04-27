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
      model: process.env.GEMINI_MODEL || "gemini-2.5-flash-lite",
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
          text: `You are a personal photo journal assistant. Analyze this image and respond with ONLY a JSON object (no markdown, no code blocks):
{
  "title": "An evocative, personal memory title (3-6 words). NOT a literal description. Think like a diary entry or photo album title. Bad: 'A man with a beard'. Good: 'Golden Hour Reflections', 'Sunday Morning Coffee', 'Lost in Thought'",
  "description": "A warm, nostalgic 1-2 sentence caption written as if recalling a personal memory. Use sensory details and emotion. Bad: 'A person standing outside'. Good: 'The afternoon light caught everything just right — one of those quiet moments worth holding onto.'",
  "tags": ["10-15 specific, detailed tags. Include ALL of: specific objects visible (laptop, coffee cup, book, car model), activity/action, setting/place type (cafe, bedroom, rooftop, kitchen), time of day (morning, golden hour, night), lighting (natural light, neon, warm glow), season/weather if visible, colors (teal, golden, muted), textures/materials (wooden, glass, concrete), atmosphere/aesthetic (cozy, urban, vintage, minimal), style if relevant (portrait, candid, flat lay), and any identifiable brands, food items, plants, animals, or architectural elements"],
  "mood": "one word mood/emotion this image evokes (e.g. serene, joyful, nostalgic, cozy, adventurous, reflective)",
  "people": [{"label": "descriptive name like 'man in blue shirt' or 'smiling child'", "description": "brief appearance description"}],
  "colors": ["top 5 dominant hex color codes from this image, e.g. #E8A87C, #41B3A3"],
  "vibes": ["2-4 aesthetic/vibe tags, e.g. cottagecore, golden hour, moody minimal, urban grit, vintage film, cozy warmth, neon nights, sun-kissed, dark academia, tropical, ethereal"]
}
If there are no people in the image, set "people" to an empty array [].
IMPORTANT: Be creative and personal with titles. Avoid generic descriptions. Tags should be SPECIFIC — prefer 'iced latte' over 'drink', 'MacBook Pro' over 'laptop', 'monstera plant' over 'plant'.`,
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
        people: [],
        colors: [],
        vibes: [],
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

  /**
   * Generate a rich recap (weekly or monthly) from memory metadata
   * @param {Object} context - { period, memoryCount, locations, moods, titles, dateRange }
   * @param {Array<string>} imageUrls - Up to 4 representative image URLs
   * @returns {Object} { story, theme, highlights }
   */
  async generateRecap(context, imageUrls = []) {
    if (!this.enabled) throw new Error("AI features not configured");

    const images = [];
    for (const url of imageUrls.slice(0, 4)) {
      try {
        const response = await fetch(url);
        if (!response.ok) continue;
        const arrayBuffer = await response.arrayBuffer();
        const base64 = Buffer.from(arrayBuffer).toString("base64");
        const mimeType = response.headers.get("content-type") || "image/jpeg";
        images.push({ inlineData: { mimeType, data: base64 } });
      } catch (e) {
        continue;
      }
    }

    const prompt = `You are creating a ${context.period} memory recap for a personal photos app.

Context:
- Period: ${context.dateRange}
- Total memories: ${context.memoryCount}
- Locations visited: ${context.locations.join(", ") || "various places"}
- Moods captured: ${context.moods.join(", ") || "mixed"}
- Memory titles: ${context.titles.slice(0, 10).join(", ") || "various moments"}

${images.length > 0 ? "I'm also sharing some representative photos from this period." : ""}

Respond with ONLY a JSON object (no markdown, no code blocks):
{
  "story": "A warm, reflective 3-4 sentence narrative about this ${context.period}. Reference specific locations and moods. Make it personal and nostalgic.",
  "theme": "A creative 2-4 word theme for this ${context.period} (e.g., 'Golden Autumn Days', 'City Adventures')",
  "highlights": ["highlight 1", "highlight 2", "highlight 3"]
}`;

    let result;
    try {
      const content =
        images.length > 0 ? [...images, { text: prompt }] : [{ text: prompt }];
      result = await this.model.generateContent(content);
    } catch (aiErr) {
      console.error(`Gemini API error (generateRecap):`, aiErr.message);
      if (aiErr.message && aiErr.message.includes("429")) {
        throw new Error("AI quota exceeded. Please try again later.");
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
      return {
        story: text.slice(0, 400),
        theme: context.period === "weekly" ? "Your Week" : "Your Month",
        highlights: [],
      };
    }
  }

  /**
   * Generate a diary-style journal entry from a day's memories
   * @param {Array} memories - Memories for the date
   * @param {string} date - The date string
   * @returns {Object} { entry, title, mood }
   */
  async generateJournalEntry(memories, date) {
    if (!this.enabled) throw new Error("AI features not configured");

    const context = memories
      .map(
        (m) =>
          `- "${m.title || "Untitled"}" at ${m.location?.name || "unknown location"} (mood: ${m.mood || "unknown"}). Tags: ${(m.tags || []).join(", ")}. ${m.description || ""}`,
      )
      .join("\n");

    const images = [];
    for (const m of memories) {
      const photo = (m.mediaItems || []).find((i) => i.type === "photo");
      if (photo && images.length < 3) {
        try {
          const response = await fetch(photo.cloudinaryUrl || photo.url);
          if (response.ok) {
            const arrayBuffer = await response.arrayBuffer();
            const base64 = Buffer.from(arrayBuffer).toString("base64");
            const mimeType =
              response.headers.get("content-type") || "image/jpeg";
            images.push({ inlineData: { mimeType, data: base64 } });
          }
        } catch (e) {
          continue;
        }
      }
    }

    const prompt = `You are a personal diary writer. Write a heartfelt, reflective journal/diary entry for ${date} based on these moments captured that day:

${context}

Respond with ONLY a JSON object (no markdown, no code blocks):
{
  "title": "A creative diary entry title for this day (3-6 words)",
  "entry": "A warm, personal 3-5 paragraph diary entry. Write in first person as if the user is reflecting on their day. Use sensory details, emotions, and connect the moments into a narrative. Reference specific places and activities. Make it feel authentic and introspective.",
  "mood": "The overall mood word for this day",
  "quote": "A short, poetic one-line quote that captures the essence of this day"
}`;

    let result;
    try {
      const content =
        images.length > 0 ? [...images, { text: prompt }] : [{ text: prompt }];
      result = await this.model.generateContent(content);
    } catch (aiErr) {
      console.error("Gemini API error (generateJournalEntry):", aiErr.message);
      if (aiErr.message && aiErr.message.includes("429")) {
        throw new Error("AI quota exceeded. Please try again later.");
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
      return {
        title: "A Day to Remember",
        entry: text.slice(0, 1000),
        mood: "reflective",
        quote: "",
      };
    }
  }

  /**
   * Generate an AI mashup/story from filtered memories
   * @param {Array} memories - Filtered memories
   * @param {string} filterDescription - How the memories were filtered
   * @returns {Object} { story, title, theme, highlights }
   */
  async generateMashup(memories, filterDescription) {
    if (!this.enabled) throw new Error("AI features not configured");

    const context = memories
      .slice(0, 15)
      .map(
        (m) =>
          `- "${m.title || "Untitled"}" (${new Date(m.createdAt).toLocaleDateString()}) at ${m.location?.name || "unknown"}. Mood: ${m.mood || "?"}. Vibes: ${(m.vibes || []).join(", ")}`,
      )
      .join("\n");

    const images = [];
    for (const m of memories.slice(0, 4)) {
      const photo = (m.mediaItems || []).find((i) => i.type === "photo");
      if (photo) {
        try {
          const response = await fetch(photo.cloudinaryUrl || photo.url);
          if (response.ok) {
            const arrayBuffer = await response.arrayBuffer();
            const base64 = Buffer.from(arrayBuffer).toString("base64");
            const mimeType =
              response.headers.get("content-type") || "image/jpeg";
            images.push({ inlineData: { mimeType, data: base64 } });
          }
        } catch (e) {
          continue;
        }
      }
    }

    const prompt = `You are creating a beautiful memory mashup/story for a personal photos app. The user has filtered their memories by: ${filterDescription}

These are the matching memories:
${context}

Respond with ONLY a JSON object (no markdown, no code blocks):
{
  "title": "A creative, evocative title for this collection (3-6 words)",
  "story": "A rich, nostalgic 4-6 sentence narrative weaving these memories together. Reference specific places, moods, and moments. Make it feel like a beautiful photo book introduction.",
  "theme": "A 2-4 word theme (e.g., 'Golden Autumn Days', 'City After Dark')",
  "highlights": ["3-5 short highlight phrases capturing key moments"]
}`;

    let result;
    try {
      const content =
        images.length > 0 ? [...images, { text: prompt }] : [{ text: prompt }];
      result = await this.model.generateContent(content);
    } catch (aiErr) {
      console.error("Gemini API error (generateMashup):", aiErr.message);
      if (aiErr.message && aiErr.message.includes("429")) {
        throw new Error("AI quota exceeded. Please try again later.");
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
      return {
        title: "Your Memories",
        story: text.slice(0, 500),
        theme: "A Collection",
        highlights: [],
      };
    }
  }
}

module.exports = new GeminiService();
