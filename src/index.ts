import { get_fetch_handler } from '../_build/js/release/build/r2-image-worker.js'

const handler = get_fetch_handler()

export default {
  fetch(request: Request, env: Cloudflare.Env, ctx: ExecutionContext) {
    return handler(request, env, ctx)
  }
}
