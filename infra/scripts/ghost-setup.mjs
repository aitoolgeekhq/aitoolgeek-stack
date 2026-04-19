#!/usr/bin/env node
/**
 * Ghost launch-kit automation.
 *
 * Usage:
 *   GHOST_API_URL=https://aitoolgeek.ai \
 *   GHOST_ADMIN_KEY=<id>:<secret> \
 *   node infra/scripts/ghost-setup.mjs
 *
 * Does everything from content/ghost/launch-kit.md:
 *  - Site settings (title, description, accent color, nav, code injection)
 *  - About page
 *  - Tools page
 *  - First post as a draft (unpublished — you launch it on Week 3 day 1)
 *  - Rename default newsletter to "The Stack"
 *  - Social URLs + meta
 *
 * Safe to re-run — idempotent (updates existing settings / pages if found by slug).
 */

import crypto from 'node:crypto';

const API_URL = (process.env.GHOST_API_URL || '').replace(/\/$/, '');
const ADMIN_KEY = process.env.GHOST_ADMIN_KEY || '';
if (!API_URL || !ADMIN_KEY || !ADMIN_KEY.includes(':')) {
  console.error('ERROR: GHOST_API_URL and GHOST_ADMIN_KEY (id:secret) env vars required');
  process.exit(1);
}
const [KEY_ID, KEY_SECRET] = ADMIN_KEY.split(':');

// -------------------- JWT -----------------------
function b64url(buf) {
  return Buffer.from(buf).toString('base64').replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}
function makeToken() {
  const header = { alg: 'HS256', typ: 'JWT', kid: KEY_ID };
  const now = Math.floor(Date.now() / 1000);
  const payload = { iat: now, exp: now + 5 * 60, aud: '/admin/' };
  const signing = `${b64url(JSON.stringify(header))}.${b64url(JSON.stringify(payload))}`;
  const sig = crypto.createHmac('sha256', Buffer.from(KEY_SECRET, 'hex')).update(signing).digest();
  return `${signing}.${b64url(sig)}`;
}

// -------------------- API helper -----------------------
async function api(method, path, body, extraHeaders = {}) {
  const url = `${API_URL}/ghost/api/admin${path}`;
  const res = await fetch(url, {
    method,
    headers: {
      Authorization: `Ghost ${makeToken()}`,
      'Content-Type': 'application/json',
      'Accept-Version': 'v5.0',
      ...extraHeaders,
    },
    body: body ? JSON.stringify(body) : undefined,
  });
  const text = await res.text();
  if (!res.ok) throw new Error(`${method} ${path} → HTTP ${res.status}\n${text.slice(0, 500)}`);
  return text ? JSON.parse(text) : {};
}

// -------------------- Settings -----------------------
// First-party proxy version — Caddy rewrites /js/sc.js and /api/event to the Plausible container.
// Avoids ad-blockers that match stats.aitoolgeek.ai/js/script.*.js.
const PLAUSIBLE_SNIPPET = `<script defer data-domain="aitoolgeek.ai" data-api="/api/event" src="/js/sc.js"></script>
<script>window.plausible = window.plausible || function() { (window.plausible.q = window.plausible.q || []).push(arguments) }</script>`;

const SETTINGS = [
  { key: 'title', value: 'AI Tool Geek' },
  { key: 'description', value: 'AI tools, remote work, and life from the Himalayas.' },
  { key: 'accent_color', value: '#C4FF00' },
  { key: 'timezone', value: 'Asia/Dubai' },
  { key: 'locale', value: 'en' },
  { key: 'codeinjection_head', value: PLAUSIBLE_SNIPPET },
  { key: 'meta_title', value: 'AI Tool Geek — AI tools + remote work from the Himalayas' },
  { key: 'meta_description', value: 'AI tools I actually use. Self-hosted stacks that save $200/mo. Remote-work playbooks. From a software engineer in Pokhara, Nepal.' },
  { key: 'og_title', value: 'AI Tool Geek' },
  { key: 'og_description', value: 'AI tools, remote work, and life from the Himalayas. By a faceless dev running his own stack.' },
  { key: 'twitter_title', value: 'AI Tool Geek' },
  { key: 'twitter_description', value: 'AI tools, remote work, and life from the Himalayas.' },
  { key: 'facebook', value: 'aitoolgeekhq' },
  { key: 'twitter', value: '@aitoolgeekhq' },
  { key: 'navigation', value: JSON.stringify([
    { label: 'Home', url: '/' },
    { label: 'The Stack', url: '/tag/stack/' },
    { label: 'Tools', url: '/tools/' },
    { label: 'About', url: '/about/' },
  ]) },
  { key: 'secondary_navigation', value: JSON.stringify([
    { label: 'YouTube', url: 'https://youtube.com/@aitoolgeekhq' },
    { label: 'X', url: 'https://x.com/aitoolgeekhq' },
    { label: 'GitHub', url: 'https://github.com/aitoolgeekhq' },
  ]) },
  { key: 'members_signup_access', value: 'all' },
  { key: 'default_content_visibility', value: 'public' },
];

// -------------------- Pages HTML -----------------------
const ABOUT_HTML = `
<h2>I'm the AI Tool Geek.</h2>

<p>I'm a remote software engineer based in Pokhara, Nepal. Five years of shipping code, most of it now with AI pair-programming. I run my AI tools on a home server in the UAE and learn everything the hard way so you don't have to.</p>

<h3>What I cover here</h3>

<p><strong>AI for developers</strong> — the tools I actually use daily, the ones I've self-hosted, and the ones I've abandoned. No hype. Real workflows.</p>

<p><strong>Remote work</strong> — I work for companies in Dubai, Europe, and the US, from a small town in the Himalayas. If you want that life too, you're in the right place.</p>

<p><strong>The Himalayan lifestyle</strong> — cost-of-living arbitrage, cafes with fiber internet, and why I left Dubai for a mountain town.</p>

<h3>The stack I run</h3>

<p>Everything here is self-hosted: Ghost for this blog, n8n for automations, Ollama + XTTS + Whisper + ComfyUI running on an RTX 4090. <strong>Zero AI SaaS subscriptions.</strong> Full details in the flagship video and at <a href="/tools/">the Tools page</a>.</p>

<h3>Stay in the loop</h3>

<p><a href="#/portal/signup">Subscribe to the newsletter</a> — one email a week, curated, no filler.</p>

<p>Or find me here:</p>
<ul>
  <li><a href="https://youtube.com/@aitoolgeekhq">YouTube</a> — deep-dives</li>
  <li><a href="https://instagram.com/aitoolgeekhq">Instagram</a> — short-form</li>
  <li><a href="https://x.com/aitoolgeekhq">X</a> — daily finds</li>
  <li><a href="https://github.com/aitoolgeekhq">GitHub</a> — open-source tools I ship</li>
</ul>

<p><em>See you in the next one.</em></p>
`.trim();

const TOOLS_HTML = `
<h2>The exact stack I use</h2>

<p>Every tool on this page I personally use. Some are affiliate links — those pay me a small commission at no cost to you, and I only list things I'd recommend to a friend. Plain honest list.</p>

<h3>AI — coding &amp; writing</h3>
<ul>
  <li><strong>Cursor</strong> — AI-first editor. My primary IDE.</li>
  <li><strong>Claude Code</strong> — Anthropic's terminal AI. Code review + multi-file refactors. Free.</li>
  <li><strong>Ollama + Qwen 2.5 Coder 32B</strong> — local LLM on my RTX 4090. Free + open source.</li>
  <li><strong>Perplexity Pro</strong> — replaced Google Search for technical questions.</li>
</ul>

<h3>AI — voice &amp; image</h3>
<ul>
  <li><strong>XTTS-v2 (Coqui)</strong> — open source voice cloning. Free, self-hosted.</li>
  <li><strong>Whisper Large-v3</strong> — transcription. Free, self-hosted.</li>
  <li><strong>ComfyUI + Flux.1 dev</strong> — image generation. Free, self-hosted.</li>
</ul>

<h3>Productivity</h3>
<ul>
  <li><strong>Notion</strong> — second brain + ideas DB.</li>
  <li><strong>Obsidian</strong> — my long-form writing space. Free.</li>
  <li><strong>Raycast</strong> — launcher + scripts. Free tier fine.</li>
</ul>

<h3>Infrastructure</h3>
<ul>
  <li><strong>n8n</strong> — self-hosted automation. Free, open source.</li>
  <li><strong>Ghost</strong> — this blog + newsletter. Free, open source.</li>
  <li><strong>Cloudflare Tunnel</strong> — public access without port forwarding. Free.</li>
  <li><strong>Resend</strong> — transactional email for the newsletter. Free under 3k/month.</li>
</ul>

<h3>Hardware</h3>
<ul>
  <li><strong>RTX 4090</strong> — the one thing that makes the whole self-hosted stack possible.</li>
  <li><strong>64 GB RAM, 2 TB NVMe</strong> — enough to run everything at once.</li>
</ul>

<h3>The full walkthrough</h3>
<p>I break down exactly how these fit together on <a href="https://youtube.com/@aitoolgeekhq">the YouTube channel</a> — video dropping Week 3 of launch.</p>

<p><em>Tools rotate in and out as I test them. This page updates.</em></p>
`.trim();

const WELCOME_POST_HTML = `
<p>If you're seeing this post, you got here early. Welcome.</p>

<p>I'm going to publish one honest thing here every week: an AI tool I'm using, a workflow I've self-hosted, a remote-work tactic that worked for me, or a slice of life from Pokhara. If any of that sounds like your thing, stick around.</p>

<p>The flagship video drops in a few days — <strong>"I replaced $200/month of AI SaaS with a home server"</strong> — a full breakdown of the stack running this very site, built on an RTX 4090 at a friend's home in Dubai while I work from Nepal.</p>

<p>Until then, poke around:</p>
<ul>
  <li><a href="/about/">About</a> — who I am, why this exists</li>
  <li><a href="/tools/">Tools I use</a> — the honest stack</li>
</ul>

<p>Thanks for being here early.</p>

<p>— AI Tool Geek</p>
`.trim();

// -------------------- Page upsert helpers -----------------------
async function upsertPage(title, slug, html, extras = {}) {
  let existing = null;
  try {
    const r = await api('GET', `/pages/slug/${slug}/`);
    existing = r.pages && r.pages[0];
  } catch (e) {
    // 404 is expected if not yet created
  }
  if (existing) {
    const { id, updated_at } = existing;
    await api('PUT', `/pages/${id}/?source=html`, {
      pages: [{ title, slug, html, status: 'published', updated_at, ...extras }],
    });
    return { id, action: 'updated' };
  }
  const r = await api('POST', '/pages/?source=html', {
    pages: [{ title, slug, html, status: 'published', ...extras }],
  });
  return { id: r.pages[0].id, action: 'created' };
}

async function upsertPost(title, slug, html, extras = {}) {
  let existing = null;
  try {
    const r = await api('GET', `/posts/slug/${slug}/`);
    existing = r.posts && r.posts[0];
  } catch (e) { /* 404 ok */ }
  if (existing) {
    const { id, updated_at } = existing;
    await api('PUT', `/posts/${id}/?source=html`, {
      posts: [{ title, slug, html, updated_at, ...extras }],
    });
    return { id, action: 'updated' };
  }
  const r = await api('POST', '/posts/?source=html', {
    posts: [{ title, slug, html, status: 'draft', ...extras }],
  });
  return { id: r.posts[0].id, action: 'created' };
}

// -------------------- Newsletter rename -----------------------
async function renameDefaultNewsletter() {
  const list = await api('GET', '/newsletters/');
  const nl = list.newsletters && list.newsletters[0];
  if (!nl) return 'no newsletter found';
  if (nl.name === 'The Stack') return 'already named "The Stack"';
  await api('PUT', `/newsletters/${nl.id}/`, {
    newsletters: [{
      name: 'The Stack',
      description: 'AI tools, remote work, and life from the Himalayas. One email a week.',
      sender_name: 'AI Tool Geek',
      updated_at: nl.updated_at,
    }],
  });
  return 'renamed';
}

// -------------------- Main -----------------------
(async () => {
  try {
    console.log(`▶ Ghost Admin API: ${API_URL}`);
    console.log(`  key id: ${KEY_ID}`);
    console.log('');

    console.log('▶ Updating site settings (one at a time to isolate any rejected key)…');
    let ok = 0, skipped = [];
    for (const setting of SETTINGS) {
      try {
        await api('PUT', '/settings/', { settings: [setting] });
        ok++;
      } catch (e) {
        skipped.push({ key: setting.key, err: e.message.split('\n')[0] });
      }
    }
    console.log(`  ✓ ${ok} applied, ${skipped.length} skipped`);
    for (const s of skipped) console.log(`    ⚠ ${s.key}: ${s.err}`);

    console.log('▶ Upserting About page…');
    const about = await upsertPage('About', 'about', ABOUT_HTML, { meta_description: "Who I am, why this exists. A remote dev in the Himalayas with a self-hosted AI stack." });
    console.log(`  ✓ ${about.action} (id ${about.id})`);

    console.log('▶ Upserting Tools page…');
    const tools = await upsertPage('Tools', 'tools', TOOLS_HTML, { meta_description: 'The exact AI + dev stack I use — some affiliate links, all honest.' });
    console.log(`  ✓ ${tools.action} (id ${tools.id})`);

    console.log('▶ Drafting welcome post (unpublished)…');
    const welcome = await upsertPost(
      'Welcome to AI Tool Geek',
      'welcome',
      WELCOME_POST_HTML,
      { tags: [{ name: 'meta' }], status: 'draft' }
    );
    console.log(`  ✓ ${welcome.action} (id ${welcome.id}) — still draft, publish manually on launch day`);

    console.log('▶ Newsletter…');
    const nl = await renameDefaultNewsletter();
    console.log(`  ✓ ${nl}`);

    console.log('');
    console.log('✅ Ghost launch kit applied.');
    console.log('');
    console.log('Next clicks still needed (Ghost UI):');
    console.log('  - Upload logo + favicon (waiting on #5)');
    console.log('  - Publish the "Welcome to AI Tool Geek" draft when you\'re ready');
    console.log('  - Verify aitoolgeek.ai domain in Resend + switch MAIL_FROM');
    console.log('');
    console.log('⚠️  IMPORTANT: rotate the Admin API key now that automation is done.');
    console.log('   Ghost → Settings → Advanced → Integrations → claude-automation → Delete');
  } catch (err) {
    console.error('\n❌ FAILED:');
    console.error(err.message);
    process.exit(1);
  }
})();
