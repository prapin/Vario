// Cloudflare Worker equivalent of vario_web.pl: serves vario.html on / and proxies
// /api?date=YYYY-MM-DD to the official V2 API, which sends no CORS header.
import html from './vario.html';

// Local midnight of a date in Switzerland, as ISO 8601 with UTC offset (+02:00 or +01:00).
// 00:00 UTC is always before the DST switch (01:00 UTC), so it has the midnight offset.
function isoMidnight(y, m, d)
{
	const t = new Date(Date.UTC(y, m - 1, d));
	const zone = new Intl.DateTimeFormat('en', { timeZone: 'Europe/Zurich', timeZoneName: 'longOffset' })
		.formatToParts(t).find(p => p.type === 'timeZoneName').value;
	return t.toISOString().slice(0, 10) + 'T00:00:00' + (zone.slice(3) || '+00:00');
}

export default {
	async fetch(request)
	{
		const url = new URL(request.url);
		if (url.pathname === '/' || url.pathname === '/index.html')
			return new Response(html, { headers: { 'content-type': 'text/html; charset=utf-8' } });

		const m = url.pathname === '/api' && /^(\d{4})-(\d\d)-(\d\d)$/.exec(url.searchParams.get('date') || '');
		if (!m)
			return new Response('Not found\n', { status: 404 });
		const api = new URL('https://api.tariffs.groupe-e.ch/v2/tariffs');
		api.searchParams.set('start_timestamp', isoMidnight(+m[1], +m[2], +m[3]));
		api.searchParams.set('end_timestamp', isoMidnight(+m[1], +m[2], +m[3] + 1));
		const res = await fetch(api);
		if (!res.ok)
			return new Response('Tariffs API request failed\n', { status: 502 });
		return new Response(res.body, { headers: { 'content-type': 'application/json', 'cache-control': 'no-cache' } });
	},
};
