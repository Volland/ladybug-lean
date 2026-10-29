import Lake
open Lake DSL System

package ladybug where
  version := v!"0.1.0"
  leanOptions := #[⟨`autoImplicit, false⟩]

/-! ## Native Ladybug library

The library version lives in `lbug.lock`. The `lbugDir` target puts the official
release library for this platform into `.lake/lbug/<version>/<platform>/` (or
uses `LBUG_LIB_DIR`), and the C shim is compiled with that library's absolute
path: it loads the library at runtime, so nothing links against it. -/

structure LbugPlatform where
  /-- Release asset suffix, e.g. `osx-arm64`. -/
  name : String
  /-- Archive extension of the release asset. -/
  archive : String
  /-- The shared library file inside it. -/
  library : String

-- @tg: implements:: [[openspec:native-library#Supported platforms]]
/-- The host platform's Ladybug release asset. -/
def lbugPlatform : LbugPlatform :=
  let arm := System.Platform.target.startsWith "aarch64" || System.Platform.target.startsWith "arm64"
  if System.Platform.isOSX then ⟨if arm then "osx-arm64" else "osx-x86_64", "tar.gz", "liblbug.dylib"⟩
  else if System.Platform.isWindows then ⟨if arm then "windows-arm64" else "windows-x86_64", "zip", "lbug_shared.dll"⟩
  else ⟨if arm then "linux-aarch64" else "linux-x86_64", "tar.gz", "liblbug.so"⟩

def readLbugLock (pkgDir : FilePath) : IO String :=
  return (← IO.FS.readFile (pkgDir / "lbug.lock")).trimAscii.toString

-- @tg: implements:: [[openspec:native-library#Pinned library version]]
-- @tg: implements:: [[openspec:native-library#Library override]]
target lbugDir pkg : FilePath := Job.async do
  if let some dir ← IO.getEnv "LBUG_LIB_DIR" then
    return FilePath.mk dir
  let ver ← readLbugLock pkg.dir
  let dir := (← IO.currentDir) / pkg.dir / ".lake" / "lbug" / ver / lbugPlatform.name
  unless ← (dir / "lbug.h").pathExists do
    IO.FS.createDirAll dir
    let asset := s!"liblbug-{lbugPlatform.name}.{lbugPlatform.archive}"
    let url := s!"https://github.com/LadybugDB/ladybug/releases/download/v{ver}/{asset}"
    logInfo s!"downloading Ladybug {ver} ({lbugPlatform.name})"
    proc { cmd := "curl", args := #["-fsSL", "-o", (dir / asset).toString, url] }
    -- bsdtar (macOS, Windows) and GNU tar both unpack .tar.gz; bsdtar also unpacks .zip.
    proc { cmd := "tar", args := #["-xf", asset], cwd := dir }
    IO.FS.removeFile (dir / asset)
  return dir

-- @tg: implements:: [[openspec:native-library#Executables find the library at runtime]]
target lbugShim.o pkg : FilePath := do
  let leanInc ← getLeanIncludeDir
  -- `CC` overrides the C compiler. Windows needs MinGW-w64 gcc: Lean's bundled
  -- clang has no C library headers there, and `lbug.h` includes <windows.h>.
  let cc := (← IO.getEnv "CC").getD (if System.Platform.isWindows then "gcc" else "cc")
  let pic := if System.Platform.isWindows then #[] else #["-fPIC"]
  let src ← inputTextFile (pkg.dir / "c" / "lbug_shim.c")
  (← lbugDir.fetch).bindM fun dir => do
    let lib := (dir / lbugPlatform.library).toString.replace "\\" "/"
    let hdr ← inputTextFile (dir / "lbug.h")
    hdr.bindM fun _ =>
      buildO (pkg.buildDir / "c" / "lbug_shim.o") src
        #["-I", leanInc.toString, "-I", dir.toString, "-I", (pkg.dir / "c").toString]
        (pic ++ #["-O2", "-Wall", s!"-DLBUG_LIB_PATH=\"{lib}\""]) cc
        (extraDepTrace := computeTrace (dir / "lbug.h"))

target libLbugShim pkg : FilePath := do
  let o ← lbugShim.o.fetch
  buildStaticLib (pkg.staticLibDir / nameToStaticLib "lbugshim") #[o]

/-- Pure core: values, decoding, schema, typed Cypher, ORM, in-memory backend. -/
lean_lib Ladybug where
  globs := #[.andSubmodules `Ladybug]

/-- Native backend over the Ladybug C API. -/
lean_lib LadybugNative where
  globs := #[.andSubmodules `LadybugNative]
  moreLinkObjs := #[libLbugShim]

lean_lib Tests where
  globs := #[.andSubmodules `Tests]

@[test_driver]
lean_exe tests where
  root := `Tests.Main

/-- Resolve the latest Ladybug release and rewrite `lbug.lock`. -/
script «lbug-update» do
  let out ← IO.Process.output {
    cmd := "curl", args := #["-fsSL", "https://api.github.com/repos/LadybugDB/ladybug/releases/latest"] }
  if out.exitCode != 0 then
    IO.eprintln s!"cannot query GitHub releases: {out.stderr}"
    return 1
  let tag ← IO.ofExcept do
    let json ← Lean.Json.parse out.stdout
    json.getObjValAs? String "tag_name"
  let ver := if tag.startsWith "v" then (tag.drop 1).toString else tag
  let old ← readLbugLock (← IO.currentDir)
  IO.FS.writeFile "lbug.lock" s!"{ver}\n"
  IO.println (if old == ver then s!"lbug.lock already at {ver}" else s!"lbug.lock: {old} -> {ver}")
  return 0
