import { env } from 'cloudflare:test'
import { describe, expect, it, beforeEach } from 'vitest'
import worker from './index'

const ctx: ExecutionContext = {
  waitUntil: () => {},
  passThroughOnException: () => {}
}

const upload = (form: FormData, auth = 'Basic ' + btoa('user:pass')) =>
  worker.fetch(
    new Request('https://example.test/upload', {
      method: 'PUT',
      headers: { Authorization: auth },
      body: form
    }),
    { ...env, USER: 'user', PASS: 'pass' },
    ctx
  )

const responseBody = async (response: Response) =>
  new TextDecoder().decode(await response.arrayBuffer())

describe('r2-image-worker', () => {
  beforeEach(async () => {
    const bucket = env.BUCKET as R2Bucket
    const objects = await bucket.list()
    await Promise.all(objects.objects.map((object) => bucket.delete(object.key)))
  })

  it('rejects upload without valid basic auth', async () => {
    const form = new FormData()
    form.set('image', new File(['hello'], 'hello.png', { type: 'image/png' }))

    const response = await upload(form, 'Basic ' + btoa('user:wrong'))

    expect(response.status).toBe(401)
    expect(response.headers.get('WWW-Authenticate')).toBe('Basic')
  })

  it('uploads an image to R2 and returns the deterministic key', async () => {
    const form = new FormData()
    form.set('image', new File(['hello'], 'hello.png', { type: 'image/png' }))
    form.set('width', '120')
    form.set('height', '80')

    const response = await upload(form)

    expect(response.status).toBe(200)
    const key = await response.text()
    expect(key).toBe('2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824_120x80.png')

    const stored = await worker.fetch(
      new Request(`https://example.test/${key}`),
      { ...env, USER: 'user', PASS: 'pass' },
      ctx
    )
    expect(stored.status).toBe(200)
    expect(stored.headers.get('Content-Type')).toContain('image/png')
    expect(await responseBody(stored)).toBe('hello')
  })

  it('hashes the uploaded image bytes instead of decoded text', async () => {
    const form = new FormData()
    const bytes = new Uint8Array([0xff, 0xfe, 0xfd, 0x00, 0x61])
    form.set('image', new File([bytes], 'binary.png', { type: 'image/png' }))

    const response = await upload(form)

    expect(response.status).toBe(200)
    const key = await response.text()
    expect(key).toBe('e42525c873fd49fed8ad1649f1630831fa5cb9188fa0b20ed8321a2e1ed8f5fc.png')

    const stored = await worker.fetch(
      new Request(`https://example.test/${key}`),
      { ...env, USER: 'user', PASS: 'pass' },
      ctx
    )
    expect(new Uint8Array(await stored.arrayBuffer())).toEqual(bytes)
  })

  it('serves a stored image with cache and content-type headers', async () => {
    const bucket = env.BUCKET as R2Bucket
    await bucket.put('stored.webp', 'image-data', {
      httpMetadata: { contentType: 'image/webp' }
    })

    const response = await worker.fetch(
      new Request('https://example.test/stored.webp'),
      { ...env, USER: 'user', PASS: 'pass' },
      ctx
    )

    expect(response.status).toBe(200)
    expect(response.headers.get('Cache-Control')).toBe('public, max-age=2592000')
    expect(response.headers.get('Content-Type')).toContain('image/webp')
    expect(await responseBody(response)).toBe('image-data')
  })

  it('returns 404 for a missing image key', async () => {
    const response = await worker.fetch(
      new Request('https://example.test/missing.png'),
      { ...env, USER: 'user', PASS: 'pass' },
      ctx
    )

    expect(response.status).toBe(404)
  })
})
