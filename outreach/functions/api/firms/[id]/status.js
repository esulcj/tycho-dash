// PUT /api/firms/:id/status — update pipeline status for a firm
export async function onRequestPut(context) {
  const { env, params } = context;
  const id = params.id;
  const headers = { "Content-Type": "application/json", "Access-Control-Allow-Origin": "*" };

  try {
    const body = await context.request.json();
    const validStatuses = [
      "not_started", "researching", "drafting", "ready_to_send",
      "sent", "replied", "meeting_scheduled"
    ];
    if (!validStatuses.includes(body.status)) {
      return new Response(JSON.stringify({ error: `Invalid status. Must be one of: ${validStatuses.join(", ")}` }), { status: 400, headers });
    }

    await env.OUTREACH_KV.put(`firm:${id}:status`, body.status);
    return new Response(JSON.stringify({ ok: true, id, field: "status" }), { status: 200, headers });
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
