import { defineWorkersConfig } from '@cloudflare/vitest-pool-workers/config'

export default defineWorkersConfig({
  test: {
    include: ['src/**/*.test.ts'],
    exclude: ['node_modules', '.mooncakes', '_build'],
    poolOptions: {
      workers: {
        isolatedStorage: false,
        miniflare: {
          r2Buckets: ['BUCKET']
        }
      }
    }
  }
})
