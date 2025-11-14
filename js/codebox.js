<script>
document.addEventListener("DOMContentLoaded", function () {
  const boxes = document.querySelectorAll('.codebox');

  boxes.forEach(box => {
    const pre = box.querySelector('pre');
    if (!pre) return;

    // Set initial width and height after layout is computed
    // Use requestAnimationFrame to ensure layout is fully ready
    requestAnimationFrame(() => {
      // Set initial width for resize handle to work properly
      if (!box.style.width) {
        const computedWidth = box.offsetWidth;
        // Only set width if we got a valid measurement
        if (computedWidth > 0) {
          box.style.width = `${computedWidth}px`;
        }
      }

      // Calculate available vertical space
      const slideSection = box.closest('section');
      if (slideSection) {
        const slideHeight = window.innerHeight;
        const boxTop = box.getBoundingClientRect().top;
        const bottomMargin = slideHeight * 0.05; // 5% bottom margin
        const availableHeight = slideHeight - boxTop - bottomMargin;

        // Set max-height to prevent overflow
        box.style.maxHeight = `${availableHeight}px`;
        box.style.overflowY = 'auto';
      }
    });

    // Ctrl+Scroll to adjust font size
    box.addEventListener('wheel', (e) => {
      if (e.ctrlKey || e.metaKey) {
        e.preventDefault();

        const currentSize = parseFloat(getComputedStyle(pre).fontSize);
        const delta = e.deltaY > 0 ? -1 : 1; // Scroll down = smaller, scroll up = larger
        const newSize = Math.max(6, Math.min(100, currentSize + delta));

        pre.style.fontSize = newSize + 'px';
      }
    }, { passive: false });

    // Handle deadCenter positioning
    if (box.classList.contains('deadCenter')) {
      requestAnimationFrame(() => placeDeadCenter(box));
    }

    // Handle scroll-to and highlight functionality
    const scrollTo = box.dataset.scrollTo;
    const highlightLines = box.dataset.highlightLines;

    if (scrollTo || highlightLines) {
      console.log('Processing codebox with scroll-to:', scrollTo, 'highlight-lines:', highlightLines);

      // Wait for content to be fully rendered
      requestAnimationFrame(() => {
        const code = box.querySelector('code');
        if (!code) {
          console.log('No code element found');
          return;
        }

        const lines = code.textContent.split('\n');
        let targetLineIndex = -1;

        // Find the line containing the scroll-to text
        if (scrollTo) {
          targetLineIndex = lines.findIndex(line => line.includes(scrollTo));
          console.log('Target line index:', targetLineIndex, 'for text:', scrollTo);
        }

        // Parse highlight data (format: "lineNum:color,lineNum:color,...")
        let highlights = {};
        if (highlightLines) {
          try {
            highlightLines.split(',').forEach(pair => {
              const [lineNum, color] = pair.trim().split(':');
              if (lineNum && color) {
                highlights[lineNum] = color;
              }
            });
            console.log('Parsed highlights:', highlights);
          } catch (e) {
            console.error('Failed to parse highlight-lines:', e, 'Raw value:', highlightLines);
          }
        }

        // Apply highlighting by wrapping lines in spans
        if (Object.keys(highlights).length > 0) {
          const wrappedLines = lines.map((line, index) => {
            const lineNum = index + 1;
            const color = highlights[lineNum];
            if (color) {
              return `<span style="background-color: ${color}33;">${escapeHtml(line)}</span>`;
            }
            return escapeHtml(line);
          });

          code.innerHTML = wrappedLines.join('\n');
        }

        // Scroll to target line (must happen after innerHTML is set)
        if (targetLineIndex >= 0) {
          const doScroll = () => {
            // Calculate approximate line height
            const computedStyle = getComputedStyle(pre);
            const lineHeight = parseFloat(computedStyle.lineHeight);
            const targetScrollTop = targetLineIndex * lineHeight;

            // Center the target line in the viewport
            const boxHeight = box.clientHeight;
            const centeredScroll = targetScrollTop - (boxHeight / 2) + (lineHeight / 2);

            console.log('Scroll heights - box.scrollHeight:', box.scrollHeight, 'box.clientHeight:', box.clientHeight, 'pre.scrollHeight:', pre.scrollHeight);
            console.log('Before scroll - box.scrollTop:', box.scrollTop, 'pre.scrollTop:', pre.scrollTop, 'setting to:', centeredScroll);

            // Try scrolling the pre element instead
            pre.scrollTop = Math.max(0, centeredScroll);

            console.log('After scroll - box.scrollTop:', box.scrollTop, 'pre.scrollTop:', pre.scrollTop);
          };

          // Try multiple times with increasing delays to fight against Reveal.js resets
          setTimeout(doScroll, 100);
          setTimeout(doScroll, 200);
          setTimeout(doScroll, 500);
          setTimeout(doScroll, 1000);

          // Also listen for Reveal.js slide events if Reveal is available
          if (typeof Reveal !== 'undefined') {
            Reveal.on('slidechanged', doScroll);
          }
        }
      });
    }
  });
});

function escapeHtml(text) {
  const div = document.createElement('div');
  div.textContent = text;
  return div.innerHTML;
}

function placeDeadCenter(box) {
  const height = box.offsetHeight;
  const targetTop = (window.innerHeight - height) / 2;

  box.style.position = 'fixed';
  box.style.left = '50%';
  box.style.transform = 'translateX(-50%)';
  box.style.top = `${targetTop}px`;
}

window.addEventListener('load', () => {
  const box = document.querySelector('.codebox.deadCenter');
  if (box) {
    setTimeout(() => placeDeadCenter(box), 100);
  }
});

</script>
