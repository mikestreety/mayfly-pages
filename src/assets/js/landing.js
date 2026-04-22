// Stars canvas
(function() {
	const canvas = document.getElementById('stars-canvas');
	const ctx = canvas.getContext('2d');

	function resize() {
		canvas.width  = window.innerWidth;
		canvas.height = window.innerHeight * 0.6;
		draw();
	}

	function rand(min, max) { return Math.random() * (max - min) + min; }

	function draw() {
		ctx.clearRect(0, 0, canvas.width, canvas.height);
		const count = Math.floor((canvas.width * canvas.height) / 3800);

		for (let i = 0; i < count; i++) {
			const x = rand(0, canvas.width);
			const yNorm = Math.random();
			const y = yNorm * canvas.height;
			const alpha = (1 - yNorm * 0.8) * rand(0.3, 1);
			const r = rand(0.4, 1.6);

			ctx.beginPath();
			ctx.arc(x, y, r, 0, Math.PI * 2);
			ctx.fillStyle = `rgba(220, 225, 255, ${alpha})`;
			ctx.fill();
		}

		for (let i = 0; i < Math.floor(count * 0.08); i++) {
			const x = rand(0, canvas.width);
			const y = rand(0, canvas.height * 0.6);
			const r = rand(1.5, 2.5);
			ctx.beginPath();
			ctx.arc(x, y, r, 0, Math.PI * 2);
			ctx.fillStyle = `rgba(200, 210, 255, ${rand(0.6, 1)})`;
			ctx.fill();
			const grd = ctx.createRadialGradient(x, y, 0, x, y, r * 4);
			grd.addColorStop(0, 'rgba(167,139,250,0.15)');
			grd.addColorStop(1, 'transparent');
			ctx.beginPath();
			ctx.arc(x, y, r * 4, 0, Math.PI * 2);
			ctx.fillStyle = grd;
			ctx.fill();
		}
	}

	window.addEventListener('resize', resize);
	resize();
})();

// Copy button
function copyCode(btn) {
	navigator.clipboard.writeText('bash <(curl -fsSL mayfly.live/preview.sh)').then(() => {
		btn.textContent = 'Copied!';
		btn.classList.add('copied');
		setTimeout(() => {
			btn.textContent = 'Copy';
			btn.classList.remove('copied');
		}, 2000);
	});
}
