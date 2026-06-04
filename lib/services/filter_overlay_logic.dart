bool shouldPaintBaseShader({
  required bool shaderLoaded,
  required bool sandboxActive,
  required bool baseFilterEnabled,
}) {
  return shaderLoaded && !sandboxActive && baseFilterEnabled;
}
