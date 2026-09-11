/**
 * The page somebody lands on when they tap a Privio channel link in WhatsApp,
 * on a website, or anywhere else that is not Privio.
 *
 * Rendered on the server, as one string, with no JavaScript and no external
 * request of any kind. That is not minimalism for its own sake:
 *
 *   - A private invite page must not leak its token. A script tag, a font from
 *     a CDN, an analytics beacon — each one is a request carrying the full URL
 *     in a `Referer` header to somebody else's server. The page therefore has
 *     no third-party anything, and the Referrer-Policy header says so too.
 *   - It has to render inside WhatsApp's in-app browser, which is not a
 *     browser anybody tests against. Plain HTML and CSS is what works there.
 *
 * Everything a template would give us is done by hand for the same reason: one
 * fewer dependency reading strings that contain invite tokens.
 */

/** HTML-escapes a string for use in element text or a quoted attribute. */
export function escapeHtml(value: string): string {
  return value
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}

/** What the page says about a channel that can be named. */
export interface ChannelPresentation {
  /** The channel's title. Only ever set for a public channel. */
  title: string;
  handle: string | null;
  description: string | null;
  memberCount: number;
  /** Absolute URL of the channel's picture, or null for the Privio mark. */
  avatarUrl: string | null;
}

export interface DownloadLinks {
  appStore: string;
  playStore: string;
  apk: string;
}

export interface InvitePageOptions {
  /** Absolute origin the page is served from, with no trailing slash. */
  origin: string;
  /** Where "Open in Privio" points. A path the app-link files claim. */
  openUrl: string;
  /** The link as shared, for the copy field and the QR code. */
  shareUrl: string;
  downloads: DownloadLinks;
}

/**
 * A private invite says nothing about the channel, and this is the type that
 * makes that structural rather than a rule somebody has to remember: there is
 * no field here to put a title in.
 */
export interface PrivateInvitePresentation {
  /** Whether the link still lets anybody in. */
  usable: boolean;
  /** Set when it does not, so the page can say which of the ways it failed. */
  problem: 'expired' | 'used_up' | null;
  /** True when joining puts the person in a queue rather than in the channel. */
  needsApproval: boolean;
}

const MARK = '/assets/privio-mark.png';

/**
 * The whole stylesheet. Inline, because a second request is a second chance
 * for the token in the URL to travel somewhere in a Referer header.
 *
 * The background is the app's true black with a faint dot grid over it — the
 * "dezentes Muster" without an image file, so there is nothing else to fetch.
 */
const STYLE = `
:root{color-scheme:dark}
*{box-sizing:border-box}
body{
  margin:0;min-height:100vh;
  background-color:#000;
  background-image:radial-gradient(#141414 1px,transparent 1px);
  background-size:22px 22px;
  color:#fff;
  font:16px/1.5 -apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,Helvetica,Arial,sans-serif;
  -webkit-font-smoothing:antialiased;
  display:flex;flex-direction:column;
}
a{color:#4ADE80}
header{
  display:flex;align-items:center;justify-content:space-between;gap:12px;
  padding:16px 20px;
}
.brand{display:flex;align-items:center;gap:10px;font-weight:600;letter-spacing:.02em}
.brand img{width:28px;height:28px;border-radius:8px}
.ghost{
  display:inline-block;padding:8px 14px;border-radius:999px;
  border:1px solid #232323;color:#A1A1A1;text-decoration:none;font-size:14px;
}
main{flex:1;display:flex;align-items:center;justify-content:center;padding:24px 20px 48px}
.card{
  width:100%;max-width:420px;
  background:#0B0B0B;border:1px solid #232323;border-radius:20px;
  padding:32px 24px;text-align:center;
}
.avatar{
  width:96px;height:96px;border-radius:50%;object-fit:cover;
  background:#0F2A1A;border:1px solid #166534;
  display:block;margin:0 auto 16px;
}
h1{font-size:22px;line-height:1.3;margin:0 0 4px;word-break:break-word}
.handle{color:#6B6B6B;font-size:14px;margin:0 0 2px}
.count{color:#A1A1A1;font-size:14px;margin:0 0 16px}
.desc{
  color:#A1A1A1;font-size:15px;margin:0 0 24px;white-space:pre-wrap;word-break:break-word;
}
.cta{
  display:block;width:100%;padding:15px 20px;border-radius:14px;
  background:#22C55E;color:#000;font-weight:600;font-size:16px;
  text-decoration:none;text-align:center;border:0;
}
.cta:active{background:#16A34A}
.note{color:#6B6B6B;font-size:13px;margin:16px 0 0}
.sub{margin-top:24px;padding-top:20px;border-top:1px solid #232323;text-align:left}
.sub h2{font-size:13px;text-transform:uppercase;letter-spacing:.08em;color:#6B6B6B;margin:0 0 10px}
.row{display:flex;gap:8px;flex-wrap:wrap}
.row a{
  flex:1 1 auto;text-align:center;padding:10px 12px;border-radius:10px;
  border:1px solid #232323;color:#fff;text-decoration:none;font-size:14px;
}
.link{
  display:block;width:100%;margin-top:10px;padding:12px;border-radius:10px;
  background:#141414;border:1px solid #232323;color:#A1A1A1;
  font:13px/1.4 ui-monospace,SFMono-Regular,Menlo,monospace;
  word-break:break-all;text-align:left;
}
.qr{margin:16px auto 0;display:block;background:#fff;border-radius:12px;padding:10px}
.bad{color:#F59E0B}
.preview{margin-top:24px;padding-top:20px;border-top:1px solid #232323;text-align:left}
.preview p{color:#6B6B6B;font-size:13px;margin:0}
footer{padding:0 20px 32px;text-align:center;color:#6B6B6B;font-size:12px}
@media(min-width:720px){
  .card{padding:40px 36px}
  h1{font-size:26px}
}
`;

interface ShellOptions {
  title: string;
  /** What a link preview should say. Never a private channel's anything. */
  ogTitle: string;
  ogDescription: string;
  ogImage: string | null;
  /** True for every private invite: a token must not reach a search index. */
  noindex: boolean;
  body: string;
  origin: string;
  downloads: DownloadLinks;
}

/** The download row, carrying only the destinations that actually exist. */
function downloadRow(downloads: DownloadLinks): string {
  const entries = [
    downloads.appStore ? { href: downloads.appStore, label: 'App Store' } : null,
    downloads.playStore ? { href: downloads.playStore, label: 'Google Play' } : null,
    downloads.apk ? { href: downloads.apk, label: 'Android APK' } : null,
  ].filter((entry): entry is { href: string; label: string } => entry !== null);

  // No invented store links. A deployment that has no listings yet says so
  // rather than showing a button that leads nowhere.
  if (entries.length === 0) {
    return `<p class="note">Privio is not in the app stores yet. Ask whoever sent
      you this link how they installed it.</p>`;
  }
  return `<div class="row">${entries
    .map((entry) => `<a href="${escapeHtml(entry.href)}">${escapeHtml(entry.label)}</a>`)
    .join('')}</div>`;
}

function shell(options: ShellOptions): string {
  const { title, ogTitle, ogDescription, ogImage, noindex, body, origin } = options;
  const hasDownload =
    options.downloads.appStore || options.downloads.playStore || options.downloads.apk;
  return `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover">
<title>${escapeHtml(title)}</title>
${noindex ? '<meta name="robots" content="noindex,nofollow">' : ''}
<meta property="og:site_name" content="Privio">
<meta property="og:type" content="website">
<meta property="og:title" content="${escapeHtml(ogTitle)}">
<meta property="og:description" content="${escapeHtml(ogDescription)}">
${ogImage ? `<meta property="og:image" content="${escapeHtml(ogImage)}">` : ''}
<meta name="twitter:card" content="summary">
<meta name="theme-color" content="#000000">
<link rel="icon" href="${MARK}">
<style>${STYLE}</style>
</head>
<body>
<header>
  <span class="brand"><img src="${MARK}" alt=""> Privio</span>
  ${hasDownload ? `<a class="ghost" href="${escapeHtml(origin)}/download">Get Privio</a>` : ''}
</header>
<main>${body}</main>
<footer>Privio — private by default.</footer>
</body>
</html>`;
}

/** The shared link, shown so it can be copied, and drawn as a QR code. */
function shareBlock(options: InvitePageOptions, qr: string | null): string {
  return `<div class="sub">
    <h2>Share this channel</h2>
    <div class="link">${escapeHtml(options.shareUrl)}</div>
    ${qr ?? ''}
  </div>`;
}

/**
 * A public channel: its real name, its real subscriber count, its real
 * description. All three are plaintext in the database because a public
 * channel is searchable, so showing them here discloses nothing that
 * discovery does not already.
 */
export function publicChannelPage(
  channel: ChannelPresentation,
  options: InvitePageOptions,
  qr: string | null,
): string {
  const avatar = channel.avatarUrl ?? MARK;
  const subscribers = `${channel.memberCount} ${
    channel.memberCount === 1 ? 'subscriber' : 'subscribers'
  }`;

  const body = `<div class="card">
    <img class="avatar" src="${escapeHtml(avatar)}" alt="">
    <h1>${escapeHtml(channel.title)}</h1>
    ${channel.handle ? `<p class="handle">@${escapeHtml(channel.handle)}</p>` : ''}
    <p class="count">${subscribers}</p>
    ${channel.description ? `<p class="desc">${escapeHtml(channel.description)}</p>` : ''}
    <a class="cta" href="${escapeHtml(options.openUrl)}">Open in Privio</a>
    <p class="note">Open this channel in Privio to read its posts and join.</p>
    ${shareBlock(options, qr)}
    <div class="preview">
      <h2 style="font-size:13px;text-transform:uppercase;letter-spacing:.08em;color:#6B6B6B;margin:0 0 10px">Channel preview</h2>
      <p>Posts are end-to-end encrypted and are not shown on the web. Open the
      channel in Privio to read them.</p>
    </div>
    <div class="sub">
      <h2>Don't have Privio?</h2>
      ${downloadRow(options.downloads)}
    </div>
  </div>`;

  return shell({
    title: `${channel.title} — Privio`,
    ogTitle: channel.title,
    ogDescription: channel.description ?? 'A channel on Privio.',
    ogImage: channel.avatarUrl ?? `${options.origin}${MARK}`,
    noindex: false,
    body,
    origin: options.origin,
    downloads: options.downloads,
  });
}

/**
 * A private invite.
 *
 * The page cannot name the channel and does not try: a private channel's title
 * is sealed with its key, which the server does not have. What it can say is
 * whether the link still works, which is the question somebody holding it
 * actually has.
 *
 * The link preview is neutral for the same reason plus one more: a preview is
 * fetched by whichever messenger the link was pasted into, so anything in it
 * travels to a third party without the sender choosing to send it.
 */
export function privateInvitePage(
  invite: PrivateInvitePresentation,
  options: InvitePageOptions,
  qr: string | null,
): string {
  const body = `<div class="card">
    <img class="avatar" src="${MARK}" alt="">
    <h1>A private channel</h1>
    <p class="count">You have been invited</p>
    <p class="desc">Its name and its posts are encrypted, so this page cannot
      show them — not to you, and not to whoever runs the server.</p>
    <a class="cta" href="${escapeHtml(options.openUrl)}">Open in Privio</a>
    <p class="note">${
      invite.needsApproval
        ? 'Opening this asks an admin to let you in. You will not see anything until they do.'
        : 'Open this invite in Privio to see the channel and join. Opening it does not join you.'
    }</p>
    ${shareBlock(options, qr)}
    <div class="sub">
      <h2>Don't have Privio?</h2>
      ${downloadRow(options.downloads)}
    </div>
  </div>`;

  return shell({
    title: 'A private channel — Privio',
    // Neutral on purpose, and identical for every private invite: the preview
    // is fetched by a messenger, not by the person who was invited.
    ogTitle: 'Privio',
    ogDescription: 'A private invitation. Open it in Privio.',
    ogImage: `${options.origin}${MARK}`,
    noindex: true,
    body,
    origin: options.origin,
    downloads: options.downloads,
  });
}

export type InviteProblem =
  | 'not_found'
  | 'deleted'
  | 'expired'
  | 'used_up';

const PROBLEMS: Record<InviteProblem, { heading: string; detail: string }> = {
  not_found: {
    heading: 'This link does not work',
    detail:
      'It may have been mistyped, or it may have been replaced. Ask whoever ' +
      'sent it for a new one.',
  },
  deleted: {
    heading: 'This channel is gone',
    detail: 'Its owner deleted it. Nothing of it is left to open.',
  },
  expired: {
    heading: 'This invitation has expired',
    detail:
      'The link was set to stop working after a time, and that time has ' +
      'passed. Ask whoever sent it for a new one.',
  },
  used_up: {
    heading: 'This invitation has been used up',
    detail:
      'The link was set to let in a certain number of people, and it has. ' +
      'Ask whoever sent it for a new one.',
  },
};

/**
 * Every way a link can fail, each said plainly.
 *
 * Deliberately not one page saying "invalid": "expired" and "used up" are
 * things the person can act on by asking for a new link, and "this channel is
 * gone" is a thing they should stop waiting for.
 *
 * All of them are noindex. An expired private invite is still a private
 * invite, and its token is still in the URL.
 */
export function problemPage(
  problem: InviteProblem,
  options: InvitePageOptions,
): string {
  const { heading, detail } = PROBLEMS[problem];
  const body = `<div class="card">
    <img class="avatar" src="${MARK}" alt="">
    <h1 class="bad">${escapeHtml(heading)}</h1>
    <p class="desc">${escapeHtml(detail)}</p>
    <div class="sub">
      <h2>Don't have Privio?</h2>
      ${downloadRow(options.downloads)}
    </div>
  </div>`;

  return shell({
    title: 'Privio',
    ogTitle: 'Privio',
    ogDescription: 'Private by default.',
    ogImage: `${options.origin}${MARK}`,
    noindex: true,
    body,
    origin: options.origin,
    downloads: options.downloads,
  });
}

/**
 * What somebody sees when the app did not open.
 *
 * Reached by the `/open/...` path when no app claimed it — which on the web is
 * indistinguishable from "the app is not installed", because a browser cannot
 * be asked. The page therefore says what it knows and offers both ways out,
 * rather than pretending to have detected anything.
 *
 * WhatsApp's in-app browser gets its own sentence: it refuses some app links
 * outright, and the fix there is to open the page in a real browser, which is
 * not obvious from inside it.
 */
export function appDidNotOpenPage(options: InvitePageOptions): string {
  const body = `<div class="card">
    <img class="avatar" src="${MARK}" alt="">
    <h1>Privio did not open</h1>
    <p class="desc">Either it is not installed on this device, or the app you
      are reading this in would not hand the link over. A browser cannot tell
      which, so here are both ways on.</p>
    <a class="cta" href="${escapeHtml(options.shareUrl)}">Try the link again</a>
    <p class="note">If you are reading this inside WhatsApp, Instagram or a
      similar app, use its menu to open the page in your browser and try again
      there. In-app browsers often refuse to hand links to other apps.</p>
    <div class="sub">
      <h2>Install Privio</h2>
      ${downloadRow(options.downloads)}
      <p class="note">After installing, open this same link again. Privio cannot
        find out on its own which invitation brought you here.</p>
    </div>
  </div>`;

  return shell({
    title: 'Open in Privio',
    ogTitle: 'Privio',
    ogDescription: 'Private by default.',
    ogImage: `${options.origin}${MARK}`,
    noindex: true,
    body,
    origin: options.origin,
    downloads: options.downloads,
  });
}
