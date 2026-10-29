import Lake
open Lake DSL System

package ladybug where
  version := v!"0.1.0"
  leanOptions := #[⟨`autoImplicit, false⟩]

/-! ## Native Ladybug library

The library version lives in `lbug.lock`. The `lbugDir` target puts the official
release library for this platform (or a copy of `LBUG_LIB_DIR`) into
`.lake/lbug/<version>/<platform>/` and rewrites its install name to that absolute
path, so every executable that links it finds it without an rpath. -/

/-- Release asset suffix for the host platform. -/
def lbugPlatform : String :=
  let arm := System.Platform.target.startsWith "aarch64" || System.Platform.target.startsWith "arm64"
  if System.Platform.isOSX then if arm then "osx-arm64" else "osx-x86_64"
  else if System.Platform.isWindows then if arm then "windows-arm64" else "windows-x86_64"
  else if arm then "linux-aarch64" else "linux-x86_64"

def readLbugLock (pkgDir : FilePath) : IO String :=
  return (← IO.FS.readFile (pkgDir / "lbug.lock")).trimAscii.toString

/-- Make the install name of the copied macOS library its absolute path. -/
def patchInstallName (dir : FilePath) : LogIO Unit := do
  if System.Platform.isOSX then
    let lib := dir / "liblbug.0.dylib"
    proc { cmd := "install_name_tool", args := #["-id", lib.toString, lib.toString] } (quiet := true)
    proc { cmd := "codesign", args := #["-f", "-s", "-", lib.toString] } (quiet := true)

-- @tg: implements:: [[openspec:native-library#Pinned library version]]
-- @tg: implements:: [[openspec:native-library#Library override]]
target lbugDir pkg : FilePath := Job.async do
  let root := (← IO.currentDir) / pkg.dir / ".lake" / "lbug"
  if let some src ← IO.getEnv "LBUG_LIB_DIR" then
    let dir := root / "override" / lbugPlatform
    IO.FS.createDirAll dir
    proc { cmd := "cp", args := #["-RPf", s!"{src}/.", dir.toString] } (quiet := true)
    unless ← (dir / "liblbug.0.dylib").pathExists do
      if System.Platform.isOSX then
        proc { cmd := "ln", args := #["-sf", "liblbug.dylib", (dir / "liblbug.0.dylib").toString] } (quiet := true)
    patchInstallName dir
    return dir
  let ver ← readLbugLock pkg.dir
  let dir := root / ver / lbugPlatform
  unless ← (dir / "lbug.h").pathExists do
    IO.FS.createDirAll dir
    let asset := s!"liblbug-{lbugPlatform}.tar.gz"
    let url := s!"https://github.com/LadybugDB/ladybug/releases/download/v{ver}/{asset}"
    logInfo s!"downloading Ladybug {ver} ({lbugPlatform})"
    proc { cmd := "curl", args := #["-fsSL", "-o", (dir / asset).toString, url] }
    proc { cmd := "tar", args := #["-xzf", asset], cwd := dir }
    IO.FS.removeFile (dir / asset)
    patchInstallName dir
  return dir

-- @tg: implements:: [[openspec:native-library#Executables find the library at runtime]]
target liblbug _pkg : Dynlib := do
  (← lbugDir.fetch).mapM fun dir => do
    let lib := dir / nameToSharedLib "lbug"
    addTrace (← computeTrace lib)
    return { path := lib, name := "lbug" }

target lbugShim.o pkg : FilePath := do
  let leanInc ← getLeanIncludeDir
  let src ← inputTextFile (pkg.dir / "c" / "lbug_shim.c")
  (← lbugDir.fetch).bindM fun dir => do
    let hdr ← inputTextFile (dir / "lbug.h")
    hdr.bindM fun _ =>
      buildO (pkg.buildDir / "c" / "lbug_shim.o") src
        #["-I", leanInc.toString, "-I", dir.toString] #["-fPIC", "-O2", "-Wall"]
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
  moreLinkLibs := #[liblbug]

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
