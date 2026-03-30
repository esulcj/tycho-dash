// PUT /api/firms/:id/email — update email draft for a firm
export async function onRequestPut(context) {
  const { env, params } = context;
  const id = params.id;
  const headers = { "Content-Type": "application/json", "Access-Control-Allow-Origin": "*" };

  try {
    const body = await context.request.json();
    if (typeof body.emailDraft !== "string") {
      return new Response(JSON.stringify({ error: "emailDraft must be a string" }), { status: 400, headers });
    }

    await env.OUTREACH_KV.put(`firm:${id}:email`, body.emailDraft);
    return new Response(JSON.stringify({ ok: true, id, field: "email" }), { status: 200, headers });
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
