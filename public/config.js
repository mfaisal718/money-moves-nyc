// Money Moves NYC — site settings. Fill in the two values from
// Supabase → Project Settings → API. The anon key is safe to publish:
// the database's Row Level Security rules decide what each person can do.
// Until these are filled in, the game runs in local mode (no accounts).
window.MM_CONFIG = {
  supabaseUrl: "https://YOUR-PROJECT.supabase.co",
  supabaseAnonKey: "YOUR-ANON-KEY",

  // Placeholder email domain for student logins. No mail is ever sent.
  studentEmailDomain: "students.moneyhubnyc.co",

  // Let classmates see each other's avatars. Uses Supabase Realtime
  // messages; set to false to turn it off.
  sharedWorld: true,

  // How often (ms) a moving avatar sends its position. Higher = fewer
  // Realtime messages, slightly choppier classmates.
  positionIntervalMs: 800
};
