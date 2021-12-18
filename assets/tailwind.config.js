const colors = require('tailwindcss/colors')

module.exports = {
  content: ['./js/**/*.js', '../lib/*_web/**/*.*ex', '../lib/*_web/**/*.sface'],
  theme: {
    extend: {
      colors: {
        gray: colors.zinc
      }
    }
  },
  plugins: [require('@tailwindcss/aspect-ratio')]
}
