const fs = require('fs');

const NEWLINES = /\n/ig;

module.exports = function logger(logDir) {
  const wStream = logDir === 'STDOUT' ? process.stdout : fs.createWriteStream(logDir, {
    flags: 'a'
  });

  return {
    log(req) {
      const payload = {
        timestamp: Date.now(),
        remoteIp: req.connection.remoteAddress,
        headers: {},
        url: req.url,
        body: ''
      };
      
      for (let i = 0; i < req.rawHeaders.length; i += 2) {
        const j = i;
        const k = i + 1;
        
        payload.headers[req.rawHeaders[j]] = req.rawHeaders[k];
      }
      
      req.on('data', (chunk) => {
        payload.body += chunk;
      });

      req.on('end', () => {
        wStream.write(JSON.stringify(payload).replace(NEWLINES, ' ') + '\n')
      });
    }
  };
};
