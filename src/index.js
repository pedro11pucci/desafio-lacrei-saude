const express = require("express")

const app = express()

app.get("/status", (req, res) => {
  res.status(200).json({ environment: process.env.APP_ENV, status: 'ok' })
})

if (require.main === module) {
  app.listen(3000, () => {
    console.log(`[${process.env.APP_ENV}] Server running on port 3000`)
  })
}

module.exports = app;