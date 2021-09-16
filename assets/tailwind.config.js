const colors = require('tailwindcss/colors')

module.exports = {
  mode: 'jit',
  purge: ['./js/**/*.js', '../lib/*_web/**/*.*ex', '../lib/*_web/**/*.sface'],
  theme: {
    extend: {
      colors: {
        gray: colors.gray,
        lime: colors.lime
      }
    }
  },
  variants: {
    extend: {}
  },
  plugins: [require('@tailwindcss/aspect-ratio')]
}
