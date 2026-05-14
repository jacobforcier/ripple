import 'dotenv/config';
import app from './app.js';

// Local development server. On Vercel the app is served via api/index.js
// instead — this file is only the entry point for `npm run dev` / `npm start`.
const PORT = process.env.PORT || 8787;

app.listen(PORT, () => {
  console.log(`Ripple backend listening on :${PORT}`);
});
