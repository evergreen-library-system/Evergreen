import { defineConfig } from 'vite'

export default defineConfig({
  test: {
    include: ['rules/**/*.eslint-test.[jt]s'],
    exclude: [],
  },
})
