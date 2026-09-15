interface WelcomeEmailTemplateProps {
  name?: string
  email: string
}

function escapeHtml(value: string): string {
  return value
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#39;")
}

export function WelcomeEmailTemplate({ name, email }: WelcomeEmailTemplateProps): string {
  const safeName = name ? escapeHtml(name) : undefined
  const safeEmail = escapeHtml(email)
  const greeting = safeName ? `Hi ${safeName},` : "Hi there,"

  return `
<!DOCTYPE html>
<html>
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1.0" />
  </head>
  <body style="margin: 0; padding: 0; background-color: #1F1F23; font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;">
    <table width="100%" cellpadding="0" cellspacing="0" style="background-color: #1F1F23; padding: 40px 20px;">
      <tr>
        <td align="center">
          <table width="100%" cellpadding="0" cellspacing="0" style="max-width: 480px; background-color: #26262b; border-radius: 8px; padding: 40px 32px;">
            <tr>
              <td>
                <p style="margin: 0 0 8px; font-size: 13px; letter-spacing: 0.15em; text-transform: uppercase; color: #9ca3af;">Tablet Notes</p>
                <h1 style="margin: 0 0 24px; font-size: 24px; font-weight: 500; color: #ffffff; line-height: 1.3;">You're on the list.</h1>
                <p style="margin: 0 0 16px; font-size: 15px; color: #d1d5db; line-height: 1.6;">${greeting}</p>
                <p style="margin: 0 0 16px; font-size: 15px; color: #d1d5db; line-height: 1.6;">
                  Thanks for signing up to be notified when Tablet Notes launches. We'll send one email to <strong style="color: #ffffff;">${safeEmail}</strong> when the app is ready for iPhone.
                </p>
                <p style="margin: 0 0 32px; font-size: 15px; color: #d1d5db; line-height: 1.6;">
                  Built for permanence. Designed for focus.
                </p>
                <p style="margin: 0; font-size: 13px; color: #6b7280; line-height: 1.5;">
                  No spam — just one email at launch.
                </p>
              </td>
            </tr>
          </table>
        </td>
      </tr>
    </table>
  </body>
</html>
  `.trim()
}
