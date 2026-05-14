// Vercel serverless entry point.
//
// An Express app is a valid (req, res) handler, so Vercel's Node runtime can
// invoke it directly. vercel.json rewrites every path to this function;
// Express's own routing takes it from there.
import app from '../src/app.js';

export default app;
