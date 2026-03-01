'use strict';

const path = require('path');

function formatNumber(n) {
  if (n == null || isNaN(n)) return '0';
  return Math.round(n).toString().replace(/\B(?=(\d{3})+(?!\d))/g, ',');
}

function formatCost(n) {
  if (n == null || isNaN(n)) return '$0.00';
  return '$' + n.toFixed(2);
}

function formatTimestamp(ts) {
  if (!ts) return '';
  const d = new Date(ts);
  const pad = (v) => String(v).padStart(2, '0');
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())} ${pad(d.getHours())}:${pad(d.getMinutes())}`;
}

function formatReport(sessions, options = {}) {
  const breakdown = options.breakdown === true;

  if (!sessions || sessions.length === 0) {
    return 'Orchestra Token Report\n' + '═'.repeat(23) + '\nNo sessions found.\n';
  }

  const totals = {
    totalInput: 0,
    totalOutput: 0,
    totalCacheCreation: 0,
    totalCacheRead: 0,
    totalCost: 0,
  };

  let firstTs = null;
  let lastTs = null;

  for (const s of sessions) {
    totals.totalInput += s.totalInput || 0;
    totals.totalOutput += s.totalOutput || 0;
    totals.totalCacheCreation += s.totalCacheCreation || 0;
    totals.totalCacheRead += s.totalCacheRead || 0;
    totals.totalCost += (s.cost && s.cost.totalCost) || 0;

    if (s.firstTimestamp) {
      const t = new Date(s.firstTimestamp);
      if (!firstTs || t < firstTs) firstTs = t;
    }
    if (s.lastTimestamp) {
      const t = new Date(s.lastTimestamp);
      if (!lastTs || t > lastTs) lastTs = t;
    }
  }

  const COL = {
    session: 25,
    input: 12,
    output: 12,
    cacheWrite: 13,
    cacheRead: 12,
    cost: 10,
  };

  const headerLine = [
    'Session'.padEnd(COL.session),
    'Input'.padStart(COL.input),
    'Output'.padStart(COL.output),
    'Cache Write'.padStart(COL.cacheWrite),
    'Cache Read'.padStart(COL.cacheRead),
    'Cost'.padStart(COL.cost),
  ].join('');

  const totalWidth = COL.session + COL.input + COL.output + COL.cacheWrite + COL.cacheRead + COL.cost;

  const lines = [];

  lines.push('Orchestra Token Report');
  lines.push('═'.repeat(23));
  lines.push(`Sessions: ${sessions.length}`);

  if (firstTs && lastTs) {
    lines.push(`Period: ${formatTimestamp(firstTs)} \u2192 ${formatTimestamp(lastTs)}`);
  }

  lines.push('');
  lines.push('  ' + headerLine);

  if (breakdown) {
    for (const s of sessions) {
      const name = s.filename ? path.basename(s.filename) : 'unknown';
      const cost = (s.cost && s.cost.totalCost) || 0;

      const row = [
        name.padEnd(COL.session),
        formatNumber(s.totalInput).padStart(COL.input),
        formatNumber(s.totalOutput).padStart(COL.output),
        formatNumber(s.totalCacheCreation).padStart(COL.cacheWrite),
        formatNumber(s.totalCacheRead).padStart(COL.cacheRead),
        formatCost(cost).padStart(COL.cost),
      ].join('');

      lines.push('  ' + row);
    }

    lines.push('  ' + '\u2500'.repeat(totalWidth));
  }

  const totalRow = [
    'TOTAL'.padEnd(COL.session),
    formatNumber(totals.totalInput).padStart(COL.input),
    formatNumber(totals.totalOutput).padStart(COL.output),
    formatNumber(totals.totalCacheCreation).padStart(COL.cacheWrite),
    formatNumber(totals.totalCacheRead).padStart(COL.cacheRead),
    formatCost(totals.totalCost).padStart(COL.cost),
  ].join('');

  lines.push('  ' + totalRow);
  lines.push('');

  return lines.join('\n');
}

module.exports = { formatReport, formatNumber, formatCost, formatTimestamp };
