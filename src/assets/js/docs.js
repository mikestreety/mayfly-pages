document.addEventListener('DOMContentLoaded', () => {

	// Theme toggle
	document.getElementById('theme-toggle').addEventListener('click', () => {
		const current = document.documentElement.getAttribute('data-theme');
		const next = current === 'dark' ? 'light' : 'dark';
		document.documentElement.setAttribute('data-theme', next);
		localStorage.setItem('mayfly-docs-theme', next);
	});

	// Build "On this page" ToC
	const headings = [...document.querySelectorAll('.content-inner h2')];
	if (headings.length > 1) {
		headings.forEach(h => {
			if (!h.id) {
				h.id = h.textContent.trim().toLowerCase().replace(/[^a-z0-9]+/g, '-');
			}
		});

		const toc = document.createElement('aside');
		toc.className = 'toc-sidebar';
		const label = document.createElement('div');
		label.className = 'toc-label';
		label.textContent = 'On this page';
		toc.appendChild(label);
		headings.forEach(h => {
			const a = document.createElement('a');
			a.className = 'toc-link';
			a.href = `#${h.id}`;
			a.textContent = h.textContent;
			toc.appendChild(a);
		});

		const layout = document.querySelector('.docs-layout');
		layout.classList.add('has-toc');
		layout.appendChild(toc);

		const links = toc.querySelectorAll('.toc-link');
		const observer = new IntersectionObserver(entries => {
			entries.forEach(entry => {
				if (entry.isIntersecting) {
					links.forEach(l => l.classList.remove('active'));
					const active = toc.querySelector(`a[href="#${entry.target.id}"]`);
					if (active) active.classList.add('active');
				}
			});
		}, { rootMargin: '-10% 0px -80% 0px' });

		headings.forEach(h => observer.observe(h));
		if (links[0]) links[0].classList.add('active');
	}

});

// Copy buttons
function copyCode(btn, text) {
	const decoded = text.replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&amp;/g, '&');
	navigator.clipboard.writeText(decoded).then(() => {
		btn.textContent = 'Copied!';
		btn.classList.add('copied');
		setTimeout(() => {
			btn.textContent = 'Copy';
			btn.classList.remove('copied');
		}, 2000);
	});
}
