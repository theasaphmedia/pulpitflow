import { serve } from "https://deno.land/std@0.177.0/http/server.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

serve(async (req) => {
  // Handle CORS preflight
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const { word } = await req.json();

    if (!word || typeof word !== "string" || word.trim().length === 0) {
      return new Response(
        JSON.stringify({ error: "A word or phrase is required." }),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    const apiKey = Deno.env.get("ANTHROPIC_API_KEY");
    if (!apiKey) {
      console.error("ANTHROPIC_API_KEY secret is not set");
      return new Response(
        JSON.stringify({ error: "Server configuration error." }),
        {
          status: 500,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    const w = word.trim();

    const prompt =
      `You are a biblical scholar, linguist, and theologian with deep expertise in Hebrew, Aramaic, and Greek.

The user has entered: "${w}"

This may be:
- A single word or phrase (e.g. "grace", "agape", "hesed") → provide a comprehensive general word study
- A word with a verse reference (e.g. "world in John 3:16", "blood in Hebrews 9:22", "faith — Romans 1:17") → study that word SPECIFICALLY as the original author used it in that verse and its immediate context. Note how the meaning may differ from other uses of the same English word elsewhere in Scripture.
- A question or natural language (e.g. "what does love mean in 1 Corinthians 13?") → interpret the intent and study accordingly.

For the "word" field in the JSON, use just the core word being studied (e.g. "world", not "world in John 3:16").
For the "root_meaning" and "full_definition", if a verse was provided, anchor the definition to how that word functions in that specific passage before broadening to general usage.
For "preachers_insight", if a verse was provided, make the insight specific to that passage.

Return ONLY valid JSON — no markdown, no code blocks, no extra text — with exactly this structure:
{
  "word": "the core word being studied",
  "original_language": "Hebrew" or "Greek" or "Aramaic" or "Hebrew & Greek",
  "transliteration": "phonetic spelling in English letters",
  "original_script": "the word written in its original alphabet",
  "strongs_number": "e.g. H157 or G26, or both if applicable",
  "root_meaning": "the core literal meaning of the root word in one sentence",
  "full_definition": "2-3 paragraph comprehensive definition covering nuance, context, and usage",
  "theological_significance": "why this word matters theologically — what is lost in translation",
  "key_usages": ["Book Chapter:Verse — brief note", "Book Chapter:Verse — brief note", "Book Chapter:Verse — brief note"],
  "related_words": ["word (meaning)", "word (meaning)", "word (meaning)"],
  "preachers_insight": "1-2 sentence practical insight a preacher can use to illuminate this word for a congregation"
}

If the English word maps to multiple original language words (e.g. "love" = agape/phileo/eros), cover the most theologically significant ones and note the distinctions.`;

    const anthropicRes = await fetch("https://api.anthropic.com/v1/messages", {
      method: "POST",
      headers: {
        "x-api-key": apiKey,
        "anthropic-version": "2023-06-01",
        "content-type": "application/json",
      },
      body: JSON.stringify({
        model: "claude-haiku-4-5-20251001",
        max_tokens: 1500,
        messages: [{ role: "user", content: prompt }],
      }),
    });

    if (!anthropicRes.ok) {
      const errText = await anthropicRes.text();
      console.error("Anthropic error:", anthropicRes.status, errText);
      return new Response(
        JSON.stringify({ error: "Word study service is temporarily unavailable." }),
        {
          status: 502,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    const anthropicData = await anthropicRes.json();
    const rawText: string = anthropicData.content[0].text;

    // Strip any accidental markdown fences
    const cleaned = rawText
      .replace(/```json/g, "")
      .replace(/```/g, "")
      .trim();

    const result = JSON.parse(cleaned);

    return new Response(JSON.stringify(result), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (e) {
    console.error("word-study function error:", e);
    return new Response(
      JSON.stringify({ error: "Could not complete word study. Please try again." }),
      {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  }
});
