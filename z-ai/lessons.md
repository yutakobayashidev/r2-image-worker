# Lessons

- When porting file upload logic, preserve the semantic data type, not just the old calls. Image hashes must be computed from `ArrayBuffer` bytes, not `File.text()`, even if the previous implementation did that.
