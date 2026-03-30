// PUT /api/firms/:id/notes — update notes and connection type for a firm
export async function onRequestPut(context) {
  const { env, params } = context;
  const id = params.id;
  const headers = { "Content-Type": "application/json", "Access-Control-Allow-Origin": "*" };

  try {
    const body = await context.request.json();
    const data = JSON.stringify({
      notes: body.notes || "",
      connectionType: body.connectionType || "",
    });

    await env.OUTREACH_KV.put(`firm:${id}:notes`, data);
    return new Response(JSON.stringify({ ok: true, id, field: "notes" }), { status: 200, headers });
  } catch (err) {
    return new Response(JSON.stringify({ error: err.message }), { status: 500, headers });
  }
}

export async function onRequestOptions() {
  return new Response(null, {
    headers: {
      "Access-Control-Allow-Origin": "*",
      "Access-Control-Allow-Methods": "PUT, OPTIONS",
      "Access-Control-Allow-Headers": "Content-Type",
    },
  });
}
