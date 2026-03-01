// Matrix rain — лёгкий фоновый эффект
(function () {
  const canvas = document.getElementById('matrix-rain');
  if (!canvas) return;

  const ctx = canvas.getContext('2d');
  const chars = 'アイウエオカキクケコサシスセソタチツテトナニヌネノハヒフヘホマミムメモヤユヨラリルレロワヲン0123456789';
  const fontSize = 10;
  let columns;
  let drops;

  function resize() {
    canvas.width = canvas.offsetWidth;
    canvas.height = canvas.offsetHeight;
    columns = Math.floor(canvas.width / fontSize);
    drops = new Array(columns).fill(0).map(() => Math.random() * -50 | 0);
  }

  function draw() {
    ctx.fillStyle = 'rgba(0, 0, 0, 0.08)';
    ctx.fillRect(0, 0, canvas.width, canvas.height);

    ctx.fillStyle = '#00FF41';
    ctx.font = fontSize + 'px monospace';

    for (let i = 0; i < columns; i++) {
      const ch = chars[Math.random() * chars.length | 0];
      const x = i * fontSize;
      const y = drops[i] * fontSize;

      if (y > 0) {
        ctx.globalAlpha = 0.4 + Math.random() * 0.6;
        ctx.fillText(ch, x, y);
      }

      drops[i]++;

      if (drops[i] * fontSize > canvas.height && Math.random() > 0.97) {
        drops[i] = 0;
      }
    }

    ctx.globalAlpha = 1;
  }

  resize();
  window.addEventListener('resize', resize);

  // ~20 FPS — лёгкая нагрузка
  setInterval(draw, 50);
})();
