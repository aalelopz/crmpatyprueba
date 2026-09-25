// Configuración de Supabase para el CRM Región San Miguel de Allende.
//
// Este archivo NO tiene efecto por sí mismo: index.html solo lee un archivo
// llamado exactamente "config.js" (sin ".example"). Para activar Supabase:
//   1. Copia este archivo y renómbralo a "config.js" (mismo directorio que
//      index.html).
//   2. Reemplaza los dos valores de abajo con los de tu proyecto de
//      Supabase (Project Settings > API).
//   3. Sube "config.js" junto con index.html a donde publiques el CRM.
//
// La URL y la "anon key" son valores PÚBLICOS por diseño de Supabase: el
// acceso real está protegido por Row Level Security (RLS), no por mantener
// estos dos valores en secreto. Aun así, nunca pongas aquí la
// "service_role key": esa sí es secreta y nunca debe llegar al navegador.
//
// Si "config.js" no existe (o se dejan los valores vacíos como están abajo),
// el CRM sigue funcionando exactamente igual que hoy: todo se guarda
// solamente en este navegador (localStorage), sin conexión a Supabase.

window.SUPABASE_CONFIG = {
  url: "", // ej: "https://abcdefghijk.supabase.co"
  anonKey: "" // ej: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9....."
};
