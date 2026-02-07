const https = require('https');
const fs = require('fs');
const path = require('path');

const API_BASE = 'https://cloud-api.yandex.net/v1/disk';

function request(options, postData = null) {
  return new Promise((resolve, reject) => {
    const req = https.request(options, (res) => {
      let data = '';
      res.on('data', (chunk) => (data += chunk));
      res.on('end', () => {
        try {
          const parsed = data ? JSON.parse(data) : {};
          if (res.statusCode >= 200 && res.statusCode < 300) {
            resolve(parsed);
          } else {
            reject(new Error(parsed.message || parsed.description || `HTTP ${res.statusCode}`));
          }
        } catch (e) {
          reject(new Error(data || `HTTP ${res.statusCode}`));
        }
      });
    });
    req.on('error', reject);
    if (postData) req.write(postData);
    req.end();
  });
}

async function getUploadUrl(token, remotePath) {
  const encoded = encodeURIComponent(remotePath);
  const options = {
    hostname: 'cloud-api.yandex.net',
    path: `/v1/disk/resources/upload?path=${encoded}&overwrite=true`,
    method: 'GET',
    headers: {
      Authorization: `OAuth ${token}`,
      Accept: 'application/json',
    },
  };
  const res = await request(options);
  return res.href;
}

function uploadFile(uploadUrl, filePath) {
  return new Promise((resolve, reject) => {
    const stream = fs.createReadStream(filePath);
    const url = new URL(uploadUrl);
    const options = {
      hostname: url.hostname,
      path: url.pathname + url.search,
      method: 'PUT',
      headers: {
        'Content-Type': 'image/png',
        'Content-Length': fs.statSync(filePath).size,
      },
    };
    const req = https.request(options, (res) => {
      if (res.statusCode === 201 || res.statusCode === 202) {
        resolve();
      } else {
        let data = '';
        res.on('data', (chunk) => (data += chunk));
        res.on('end', () => reject(new Error(data || `HTTP ${res.statusCode}`)));
      }
    });
    req.on('error', reject);
    stream.pipe(req);
  });
}

async function uploadToYandexDisk(filePath, token) {
  const fileName = path.basename(filePath);
  const remotePath = `/Scrinsjater/${fileName}`;
  const uploadUrl = await getUploadUrl(token, remotePath);
  await uploadFile(uploadUrl, filePath);
  return `https://disk.yandex.ru/client/disk/Scrinsjater`;
}

module.exports = { uploadToYandexDisk };
