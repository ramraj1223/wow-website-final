// Sends an email notification (via Resend) whenever a lead form is submitted.
// Requires two Netlify environment variables, set in Site settings → Environment variables:
//   RESEND_API_KEY    — API key from https://resend.com
//   LEAD_NOTIFY_EMAIL — the inbox that should receive new-lead alerts

exports.handler = async (event) => {
  if (event.httpMethod !== 'POST') {
    return { statusCode: 405, body: 'Method Not Allowed' };
  }

  const RESEND_API_KEY = process.env.RESEND_API_KEY;
  const NOTIFY_EMAIL   = process.env.LEAD_NOTIFY_EMAIL;

  if (!RESEND_API_KEY || !NOTIFY_EMAIL) {
    console.error('Missing RESEND_API_KEY or LEAD_NOTIFY_EMAIL environment variable');
    return { statusCode: 500, body: 'Email notification is not configured' };
  }

  let lead;
  try {
    lead = JSON.parse(event.body);
  } catch (err) {
    return { statusCode: 400, body: 'Invalid JSON' };
  }

  const escapeHtml = (str) => String(str).replace(/[&<>"']/g, (c) => (
    { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]
  ));

  const rows = [
    ['Name', lead.name],
    ['Phone', lead.phone],
    ['Email', lead.email],
    ['Project Type', lead.project_type],
    ['Timeline', lead.timeline],
    ['Address', lead.address],
    ['Estimated Total', lead.estimate_total ? `$${Number(lead.estimate_total).toLocaleString('en-US')}` : null],
    ['Message', lead.message],
    ['Source', lead.source],
  ].filter(([, value]) => value);

  const html = `
    <div style="font-family: Arial, sans-serif; max-width: 560px; margin: 0 auto;">
      <h2 style="color:#1A2B4A;">New Lead: ${escapeHtml(lead.name || 'Unknown')}</h2>
      <table style="width:100%; border-collapse: collapse;">
        ${rows.map(([label, value]) => `
          <tr>
            <td style="padding:8px; border-bottom:1px solid #eee; font-weight:600; color:#3A3028; width:140px;">${escapeHtml(label)}</td>
            <td style="padding:8px; border-bottom:1px solid #eee; color:#3A3028;">${escapeHtml(value)}</td>
          </tr>
        `).join('')}
      </table>
      <p style="margin-top:20px; font-size:12px; color:#7A6E65;">Submitted via ${escapeHtml(lead.source || 'website')} on the WOW Home Transformations site.</p>
    </div>
  `;

  try {
    const res = await fetch('https://api.resend.com/emails', {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${RESEND_API_KEY}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        from: 'WOW Home Transformations <leads@wowhometransformations.com>',
        to: [NOTIFY_EMAIL],
        subject: `New Lead: ${lead.name || 'Someone'} — ${lead.project_type || lead.source || 'Website'}`,
        html,
      }),
    });

    if (!res.ok) {
      const text = await res.text();
      console.error('Resend API error:', res.status, text);
      return { statusCode: 502, body: 'Failed to send notification email' };
    }

    return { statusCode: 200, body: JSON.stringify({ ok: true }) };
  } catch (err) {
    console.error('Error sending notification email:', err);
    return { statusCode: 500, body: 'Error sending notification email' };
  }
};
