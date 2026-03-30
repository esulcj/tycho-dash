// GET /api/firms — return all firms with dossiers, quotes, email drafts
export async function onRequestGet(context) {
  const { env } = context;
  const headers = { "Content-Type": "application/json", "Access-Control-Allow-Origin": "*" };

  try {
    // Get firms list from KV
    const firmsRaw = await env.OUTREACH_KV.get("firms", "json");
    if (!firmsRaw) {
      return new Response(JSON.stringify({ error: "No firms data. Run seed script." }), { status: 404, headers });
    }

    // Merge in any per-firm overrides (emails, notes, status)
    const firms = await Promise.all(firmsRaw.map(async (firm) => {
      const id = slugify(firm.name);
      const [emailDraft, notes, status] = await Promise.all([
        env.OUTREACH_KV.get(`firm:${id}:email`),
        env.OUTREACH_KV.get(`firm:${id}:notes`),
        env.OUTREACH_KV.get(`firm:${id}:status`),
      ]);
      let parsedNotes = "";
      let connectionType = "";
      if (notes) {
        try {
          const n = JSON.parse(notes);
          parsedNotes = n.notes || "";
          connectionType = n.connectionType || "";
        } catch { parsedNotes = notes; }
      }
      return {
        ...firm,
        id,
        emailDraft: emailDraft || firm.emailDraft || "",
        userNotes: parsedNotes,
        connectionType,
        pipelineStatus: status || firm.pipelineStatus || "not_started",
      };
    }));

    // Get quotes keyed by firm name
    const quotesRaw = await env.OUTREACH_KV.get("quotes", "json");
    const quotesMap = {};
    if (quotesRaw) {
      for (const q of quotesRaw) {
        quotesMap[q.firmName] = q;
      }
    }

    // Attach quotes to firms
    for (const firm of firms) {
      const match = quotesMap[firm.name];
      firm.quotes = match ? match.quotes : [];
      firm.quotesContact = match ? match.contactName : "";
    }

    return new Response(JSON.stringify(firms), { status: 200, headers });
  } catch (err) {
    return new Response(JSON.stringify({ error: err.message }), { status: 500, headers });
  }
}

export async function onRequestOptions() {
  return new Response(null, {
    headers: {
      "Access-Control-Allow-Origin": "*",
      "Access-Control-Allow-Methods": "GET, OPTIONS",
      "Access-Control-Allow-Headers": "Content-Type",
    },
  });
}

function slugify(name) {
  return name.toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/(^-|-$)/g, "");
}
