#!/usr/bin/env node
/**
 * html-to-pdf.js - Convert reveal.js HTML presentations to 16:9 PDF using Playwright
 *
 * This script uses Playwright's Chromium browser to render HTML presentations
 * and export them as high-quality PDFs with a 16:9 aspect ratio.
 *
 * Usage: node html-to-pdf.js <input.html> <output.pdf>
 */

const { chromium } = require('playwright');
const path = require('path');
const fs = require('fs');

// 16:9 aspect ratio dimensions (4K resolution for high quality)
const WIDTH = 3840;
const HEIGHT = 2160;

async function htmlToPdf(htmlFile, outputPdf, width = WIDTH, height = HEIGHT) {
  // Validate input file exists
  if (!fs.existsSync(htmlFile)) {
    console.error(`Error: Input file '${htmlFile}' not found`);
    process.exit(1);
  }

  console.log(`Converting ${htmlFile} to PDF at ${width}x${height}...`);

  const browser = await chromium.launch({
    headless: true,  // Show the browser window for debugging
    devtools: false    // Open DevTools automatically
  });

  try {
    const page = await browser.newPage();

    // Set 16:9 viewport
    await page.setViewportSize({
      width: width,
      height: height
    });

    // Load the HTML file using file:// protocol
    const absolutePath = path.resolve(htmlFile);
    const fileUrl = `file://${absolutePath}`;

    console.log(`Loading ${fileUrl}...`);
    await page.goto(fileUrl, {
      waitUntil: 'networkidle'  // Wait for all resources to load
    });

    // IMPORTANT: Emulate screen media instead of print to preserve screen CSS
    await page.emulateMedia({ media: 'screen' });

    // Wait a bit more for reveal.js to initialize and render math
    await page.waitForTimeout(2000);

    // Check if reveal.js is present and get slide count
    const slideInfo = await page.evaluate(() => {
      if (typeof Reveal !== 'undefined') {
        const totalSlides = Reveal.getTotalSlides();
        const indices = [];
        // Get all slide indices
        for (let h = 0; h < Reveal.getHorizontalSlides().length; h++) {
          const horizontalSlide = Reveal.getHorizontalSlides()[h];
          const verticalSlides = horizontalSlide.querySelectorAll('section');
          if (verticalSlides.length > 1) {
            for (let v = 0; v < verticalSlides.length; v++) {
              indices.push({ h, v });
            }
          } else {
            indices.push({ h, v: 0 });
          }
        }
        return {
          hasReveal: true,
          totalSlides: totalSlides,
          indices: indices
        };
      }
      return { hasReveal: false };
    });

    if (!slideInfo.hasReveal) {
      console.error('Error: reveal.js not detected');
      process.exit(1);
    }

    console.log(`Detected reveal.js presentation with ${slideInfo.totalSlides} slides`);
    console.log('Generating PDF by rendering each slide...');

    // Generate PDFs for each slide
    const { PDFDocument } = require('pdf-lib');
    const finalPdf = await PDFDocument.create();

    for (let i = 0; i < slideInfo.indices.length; i++) {
      const { h, v } = slideInfo.indices[i];
      console.log(`Rendering slide ${i + 1}/${slideInfo.totalSlides} (h:${h}, v:${v})...`);

      // Navigate to the specific slide
      await page.evaluate(({ h, v }) => {
        Reveal.slide(h, v);
      }, { h, v });

      // Wait for slide transition and rendering
      await page.waitForTimeout(500);

      // Generate PDF for this single slide
      const tempPdfPath = `/tmp/slide_${i}.pdf`;
      await page.pdf({
        path: tempPdfPath,
        width: `${width}px`,
        height: `${height}px`,
        printBackground: true,
        preferCSSPageSize: false,
        margin: { top: 0, right: 0, bottom: 0, left: 0 }
      });

      // Load and merge into final PDF
      const tempPdfBytes = fs.readFileSync(tempPdfPath);
      const tempPdf = await PDFDocument.load(tempPdfBytes);
      const [copiedPage] = await finalPdf.copyPages(tempPdf, [0]);
      finalPdf.addPage(copiedPage);

      // Clean up temp file
      fs.unlinkSync(tempPdfPath);
    }

    // Save the final merged PDF
    const finalPdfBytes = await finalPdf.save();
    fs.writeFileSync(outputPdf, finalPdfBytes);

    console.log(`Successfully created ${outputPdf}`);

    // Keep browser open for debugging - press Ctrl+C in terminal to close
    // console.log('\nBrowser window is open for inspection. Press Ctrl+C to close...');
    // await new Promise(() => {}); // Wait indefinitely

  } catch (error) {
    console.error('Error during PDF generation:', error);
    process.exit(1);
  } finally {
    await browser.close();
  }
}

// Main entry point
async function main() {
  const args = process.argv.slice(2);

  if (args.length < 2) {
    console.error('Usage: node html-to-pdf.js <input.html> <output.pdf> [width] [height]');
    console.error('  width, height: Optional resolution (default: 3840x2160 for 4K)');
    console.error('  Common presets:');
    console.error('    - 1920 1080 (1080p)');
    console.error('    - 2560 1440 (1440p)');
    console.error('    - 3840 2160 (4K, default)');
    process.exit(1);
  }

  const [htmlFile, outputPdf, widthArg, heightArg] = args;

  // Override global WIDTH and HEIGHT if provided
  if (widthArg && heightArg) {
    const customWidth = parseInt(widthArg, 10);
    const customHeight = parseInt(heightArg, 10);

    if (isNaN(customWidth) || isNaN(customHeight) || customWidth <= 0 || customHeight <= 0) {
      console.error('Error: Width and height must be positive integers');
      process.exit(1);
    }

    // Temporarily override constants by passing them to htmlToPdf
    await htmlToPdf(htmlFile, outputPdf, customWidth, customHeight);
  } else {
    await htmlToPdf(htmlFile, outputPdf);
  }
}

main().catch(error => {
  console.error('Fatal error:', error);
  process.exit(1);
});
