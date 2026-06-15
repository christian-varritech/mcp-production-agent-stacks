const puppeteer = require('puppeteer');
const path = require('path');

(async () => {
  const browser = await puppeteer.launch({
    headless: 'new',
    args: ['--no-sandbox', '--disable-setuid-sandbox']
  });
  
  const page = await browser.newPage();
  const htmlPath = path.join(__dirname, 'post.html');
  
  await page.setViewport({ width: 1200, height: 1200, deviceScaleFactor: 2 });
  await page.goto(`file://${htmlPath}`, { waitUntil: 'networkidle0' });
  await page.screenshot({
    path: path.join(__dirname, 'post.png'),
    fullPage: true
  });
  
  await browser.close();
  console.log('✅ Image rendered: post.png');
})();
