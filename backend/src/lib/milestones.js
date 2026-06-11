// Milestones — computed entirely from existing tables (no new writes).
//
// Design rule: celebrate ACTIONS AND CLICKS (instant, in the user's control),
// reward EARNINGS with tiers (slow but real). Milestones here are the
// checklist + the three celebration moments' source of truth; the app decides
// when/how to animate. Tiers never decay; milestones never un-achieve.

import { tierProgress } from './tiers.js';

/**
 * Compute the user's milestone checklist + tier card.
 * Reads: link_stats (links + clicks), links (retailers), group_members,
 * user_earnings. Returns { tier, milestones: [{id,title,achieved,detail}] }.
 */
export async function computeMilestones(db, userId) {
  const [links, stats, groups, earnings] = await Promise.all([
    db.from('links').select('retailer').eq('user_id', userId),
    db.from('link_stats').select('click_count').eq('user_id', userId),
    db.from('group_members').select('group_id').eq('user_id', userId),
    db.from('user_earnings').select('*').eq('user_id', userId).maybeSingle(),
  ]);
  for (const r of [links, stats, groups, earnings]) {
    if (r.error) throw new Error(`milestone query failed: ${r.error.message}`);
  }

  const linkCount = links.data?.length ?? 0;
  const retailers = new Set((links.data ?? []).map((l) => l.retailer).filter(Boolean));
  const clicks = (stats.data ?? []).reduce((s, r) => s + (r.click_count ?? 0), 0);
  const groupCount = groups.data?.length ?? 0;
  const e = earnings.data ?? { lifetime_cents: 0, pending_cents: 0, confirmed_cents: 0, paid_cents: 0 };
  const lifetimeConfirmed = (e.confirmed_cents ?? 0) + (e.paid_cents ?? 0);

  const usd = (c) => `$${(c / 100).toFixed(2)}`;
  const milestones = [
    { id: 'first_link',     title: 'Share your first link',            achieved: linkCount >= 1,  detail: `${linkCount} link${linkCount === 1 ? '' : 's'} created` },
    { id: 'first_click',    title: 'A friend clicks your link',        achieved: clicks >= 1,     detail: `${clicks} click${clicks === 1 ? '' : 's'} so far` },
    { id: 'three_retailers',title: 'Share from 3 different retailers', achieved: retailers.size >= 3, detail: `${retailers.size}/3 retailers` },
    { id: 'ten_clicks',     title: '10 clicks across your links',      achieved: clicks >= 10,    detail: `${Math.min(clicks, 10)}/10 clicks` },
    { id: 'first_group',    title: 'Join or start a group',            achieved: groupCount >= 1, detail: groupCount ? 'in a group' : 'not yet' },
    { id: 'first_earnings', title: 'First earnings ripple in',         achieved: e.lifetime_cents > 0, detail: e.lifetime_cents > 0 ? `${usd(e.lifetime_cents)} lifetime` : 'waiting on your first sale' },
    { id: 'first_confirmed',title: 'Earnings confirmed & cashable',    achieved: lifetimeConfirmed > 0, detail: lifetimeConfirmed > 0 ? `${usd(lifetimeConfirmed)} confirmed` : 'clears ~60 days after a sale' },
    { id: 'first_payout',   title: 'Your first payout',                achieved: (e.paid_cents ?? 0) > 0, detail: e.paid_cents > 0 ? `${usd(e.paid_cents)} paid out` : 'monthly, $10 minimum' },
  ];

  return { tier: tierProgress(lifetimeConfirmed), milestones };
}
