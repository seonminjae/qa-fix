/** @type {import('tailwindcss').Config} */
export default {
  content: ['./src/renderer/index.html', './src/renderer/src/**/*.{ts,tsx}'],
  theme: {
    extend: {
      colors: {
        surface: {
          0: '#0d1117',
          1: '#161b22',
          2: '#1f242c',
          3: '#282f3a'
        },
        severity: {
          critical: '#ff6b6b',
          major: '#ffa94d',
          minor: '#ffd43b',
          trivial: '#8ce99a',
          unknown: '#868e96'
        }
      }
    }
  },
  plugins: []
}
