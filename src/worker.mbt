///|
let cache_control = "public, max-age=2592000"

///|
#external
priv type ImagesBinding

///|
priv struct ImageTransformParameters {
  width : Int?
  height : Int?
  quality : Int?
}

///|
extern "js" fn request_form_data(
  req : @cloudflare.CloudflareRequest,
) -> @js_async.Promise[@http.FormData] =
  #| (req) => req.formData()

///|
extern "js" fn form_file(fd : @http.FormData, name : String) -> @file.File? =
  #| (fd, name) => {
  #|   const value = fd.get(name);
  #|   return value instanceof File ? value : undefined;
  #| }

///|
extern "js" fn form_string(fd : @http.FormData, name : String) -> String? =
  #| (fd, name) => {
  #|   const value = fd.get(name);
  #|   return typeof value === "string" && value.length > 0 ? value : undefined;
  #| }

///|
extern "js" fn file_array_buffer(
  file : @file.File,
) -> @js_async.Promise[@arraybuffer.ArrayBuffer] =
  #| (file) => file.arrayBuffer()

///|
extern "js" fn headers_new() -> @http.Headers =
  #| () => new Headers()

///|
extern "js" fn headers_set(
  headers : @http.Headers,
  name : String,
  value : String,
) -> Unit =
  #| (headers, name, value) => headers.set(name, value)

///|
extern "js" fn response_stream(
  body : @streams.ReadableStream,
  status : Int,
  headers : @http.Headers,
) -> @http.Response =
  #| (body, status, headers) => new Response(body, { status, headers })

///|
extern "js" fn unauthorized_response() -> @http.Response =
  #| () => new Response("Unauthorized", {
  #|   status: 401,
  #|   headers: { "WWW-Authenticate": "Basic" },
  #| })

///|
extern "js" fn btoa(value : String) -> String =
  #| (value) => btoa(value)

///|
extern "js" fn sha256_hex(
  value : @arraybuffer.ArrayBuffer,
) -> @js_async.Promise[String] =
  #| async (value) => {
  #|   const digest = await crypto.subtle.digest("SHA-256", value);
  #|   return [...new Uint8Array(digest)]
  #|     .map((byte) => byte.toString(16).padStart(2, "0"))
  #|     .join("");
  #| }

///|
extern "js" fn parse_int_option(value : String) -> Int? =
  #| (value) => {
  #|   if (!/^-?\d+$/.test(value)) return undefined;
  #|   const parsed = Number(value);
  #|   return Number.isSafeInteger(parsed) ? parsed : undefined;
  #| }

///|
extern "js" fn images_transform_response(
  images : ImagesBinding,
  stream : @streams.ReadableStream,
  width : Int?,
  height : Int?,
  quality : Int?,
  format : String,
) -> @js_async.Promise[@http.Response] =
  #| async (images, stream, width, height, quality, format) => {
  #|   const parameters = {};
  #|   if (width !== undefined) parameters.width = width;
  #|   if (height !== undefined) parameters.height = height;
  #|   if (quality !== undefined) parameters.quality = quality;
  #|   const output = { format };
  #|   if (quality !== undefined) output.quality = quality;
  #|   const result = await images.input(stream).transform(parameters).output(output);
  #|   return result.response();
  #| }

///|
extern "js" fn response_set_header(
  response : @http.Response,
  name : String,
  value : String,
) -> Unit =
  #| (response, name, value) => response.headers.set(name, value)

///|
fn env_r2(env : @cloudflare.CloudflareEnv) -> @cloudflare.R2Bucket {
  env.get("BUCKET").unwrap().cast()
}

///|
fn env_images(env : @cloudflare.CloudflareEnv) -> ImagesBinding? {
  match env.get("IMAGES") {
    Some(value) => Some(value.cast())
    None => None
  }
}

///|
fn env_string(env : @cloudflare.CloudflareEnv, name : String) -> String {
  env.get_string(name).unwrap_or("")
}

///|
fn is_authorized(
  req : @cloudflare.CloudflareRequest,
  env : @cloudflare.CloudflareEnv,
) -> Bool {
  let expected = "Basic " +
    btoa(env_string(env, "USER") + ":" + env_string(env, "PASS"))
  req.header("Authorization").unwrap_or("") == expected
}

///|
fn extension_for(content_type : String) -> String {
  match content_type {
    "image/avif" => "avif"
    "image/gif" => "gif"
    "image/jpeg" => "jpg"
    "image/png" => "png"
    "image/svg+xml" => "svg"
    "image/webp" => "webp"
    _ => "png"
  }
}

///|
fn preferred_content_type(accept : String?, fallback : String) -> String {
  match accept {
    Some(value) =>
      if value.contains("image/avif") {
        "image/avif"
      } else if value.contains("image/webp") {
        "image/webp"
      } else {
        fallback
      }
    None => fallback
  }
}

///|
fn int_query(params : @url.URLSearchParams, name : String) -> Int? {
  match params.get(name) {
    Some(value) => parse_int_option(value)
    None => None
  }
}

///|
fn image_parameters(params : @url.URLSearchParams) -> ImageTransformParameters? {
  let mut width = None
  let mut height = None
  let mut quality = None
  if int_query(params, "width") is Some(value) {
    width = Some(value)
  } else if params.get("width") is Some(_) {
    return None
  }
  if int_query(params, "height") is Some(value) {
    height = Some(value)
  } else if params.get("height") is Some(_) {
    return None
  }
  if int_query(params, "quality") is Some(value) {
    quality = Some(value)
  } else if params.get("quality") is Some(_) {
    return None
  }
  Some({ width, height, quality })
}

///|
async fn sha256_array_buffer(buffer : @arraybuffer.ArrayBuffer) -> String {
  sha256_hex(buffer).wait()
}

///|
async fn handle_upload(
  req : @cloudflare.CloudflareRequest,
  env : @cloudflare.CloudflareEnv,
) -> @http.Response {
  if !is_authorized(req, env) {
    return unauthorized_response()
  }

  let form = request_form_data(req).wait()
  let image = match form_file(form, "image") {
    Some(file) => file
    None => return @http.Response::text_("Missing image", 400)
  }
  let content_type = image.contentType()
  let extension = extension_for(content_type)
  let body = file_array_buffer(image).wait()
  let hash = sha256_array_buffer(body)
  let key = match (form_string(form, "width"), form_string(form, "height")) {
    (Some(width), Some(height)) =>
      hash + "_" + width + "x" + height + "." + extension
    _ => hash + "." + extension
  }

  let metadata : @cloudflare.R2HttpMetadata = {
    contentType: Some(content_type),
    contentLanguage: None,
    contentDisposition: None,
    contentEncoding: None,
    cacheControl: None,
    cacheExpiry: None,
  }
  let _ = env_r2(env).put(key, @core.any(body), httpMetadata=metadata)
  @http.Response::text_(key, 200)
}

///|
async fn handle_get(
  req : @cloudflare.CloudflareRequest,
  env : @cloudflare.CloudflareEnv,
) -> @http.Response {
  let url = @url.URL::new(req.url)
  let key = url.pathname[1:].to_owned()
  let object = env_r2(env).get(key)
  let object = match object {
    Some(value) => value
    None => return @http.Response::text_("404 Not Found", 404)
  }
  let http_metadata = object.http_metadata()
  let content_type_value = http_metadata["contentType"]
  let content_type = if @core.typeof_(content_type_value) == "string" {
    content_type_value.cast()
  } else {
    ""
  }
  let params = url.searchParams()

  if url.search.length() > 0 {
    match (env_images(env), image_parameters(params)) {
      (Some(images), Some(parameters)) => {
        let format = preferred_content_type(req.header("Accept"), content_type)
        let response = images_transform_response(
          images,
          object.body(),
          parameters.width,
          parameters.height,
          parameters.quality,
          format,
        ).wait()
        response_set_header(response, "Cache-Control", cache_control)
        return response
      }
      _ => ()
    }
  }

  let headers = headers_new()
  headers_set(headers, "Cache-Control", cache_control)
  headers_set(headers, "Content-Type", content_type)
  response_stream(object.body(), 200, headers)
}

///|
pub fn get_fetch_handler() -> @cloudflare.CloudflareFetchHandler {
  let async_handler = async fn(
    req : @cloudflare.CloudflareRequest,
    env : @cloudflare.CloudflareEnv,
    _ctx : @cloudflare.CloudflareContext,
  ) -> @http.Response {
    if req.method_() == "PUT" && @url.URL::new(req.url).pathname == "/upload" {
      handle_upload(req, env)
    } else if req.method_() == "GET" {
      handle_get(req, env)
    } else {
      @http.Response::text_("404 Not Found", 404)
    }
  }
  (req, env, ctx) => {
    @core.identity(
      @js_async.Promise::from_async(() => async_handler(req, env, ctx)),
    )
  }
}
