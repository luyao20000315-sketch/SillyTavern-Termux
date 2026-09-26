// ═══════════════════════════════════════════════════════════════════
//  mark-inject.js · 酒馆页面标记注入器
//  在酒馆 index.html 的 </body> 前注入一行底部小标记
//  开源程序 · 仅供学习交流使用 · 完全免费
//
//  用法（默认找 ~/SillyTavern/public/index.html）:
//    node mark-inject.js
//  指定路径:
//    node mark-inject.js --target=/path/to/SillyTavern/public/index.html
// ═══════════════════════════════════════════════════════════════════
const fs = require('fs');
const os = require('os');
const path = require('path');

// 默认目标：用户主目录下的 SillyTavern（Termux 上就是 $HOME/SillyTavern）
const DEFAULT_TARGET = path.join(os.homedir(), 'SillyTavern', 'public', 'index.html');

const argTarget = process.argv.find(a => a.startsWith('--target='));
const FILE = argTarget ? argTarget.split('=')[1] : DEFAULT_TARGET;

// 标记 id（改这里同时要改 index.html 里的引用）
const MARKER_ID = 'ST_BADGE';

// 定制标记（改这里即可）
const MARKER = `<!-- ══ 定制标记 · 开源仅供学习交流 ══ -->
<style>
  #${MARKER_ID}{position:fixed;bottom:6px;left:50%;transform:translateX(-50%);z-index:99999;
    background:rgba(0,0,0,.55);color:#fff;font-size:10px;padding:2px 10px;border-radius:20px;
    letter-spacing:.5px;pointer-events:none;white-space:nowrap;opacity:.75;backdrop-filter:blur(4px)}
</style>
<div id="${MARKER_ID}">开源程序 · 仅供学习交流 · 完全免费</div>
<!-- ══ 定制标记结束 ══ -->`;

if (!fs.existsSync(FILE)) {
  console.error('[!] 未找到 index.html:', FILE);
  console.error('    用法: node mark-inject.js --target=/path/to/SillyTavern/public/index.html');
  process.exit(1);
}

let html = fs.readFileSync(FILE, 'utf8');

// 幂等：已注入则跳过
if (html.includes(MARKER_ID)) {
  console.log('[*] 定制标记已存在，跳过。');
  process.exit(0);
}

// 注入到 </body> 前
if (html.includes('</body>')) {
  html = html.replace('</body>', MARKER + '\n</body>');
} else {
  // 兜底：追加到文件末尾
  html += '\n' + MARKER + '\n';
}

fs.writeFileSync(FILE, html, 'utf8');
console.log('[✔] 定制标记注入完成:', FILE);
console.log('    开源程序 · 仅供学习交流使用 · 完全免费');
