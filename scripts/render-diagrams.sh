#!/usr/bin/env bash
set -Eeuo pipefail

root_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
state_dir="$root_dir/.state"
output_dir="$root_dir/docs/c4"
check_only=0

if [[ ${1-} == --check ]]; then
  check_only=1
elif [[ $# -ne 0 ]]; then
  printf 'Usage: %s [--check]\n' "$0" >&2
  exit 2
fi

command -v docker >/dev/null 2>&1 || {
  printf 'docker is required to render C4 diagrams.\n' >&2
  exit 1
}

structurizr_image='structurizr/cli:2025.11.09'
plantuml_image='plantuml/plantuml:1.2026.6'

mkdir -p "$state_dir" "$output_dir"
build_dir=$(mktemp -d "$state_dir/c4-render.XXXXXX")
trap 'rm -rf "$build_dir"' EXIT

docker run --rm \
  --user "$(id -u):$(id -g)" \
  --workdir /usr/local/structurizr \
  --volume "$root_dir/docs/c4/src:/usr/local/structurizr/docs/c4/src:ro" \
  --volume "$build_dir:/usr/local/structurizr/.state/c4-render" \
  "$structurizr_image" export \
  -workspace docs/c4/src/workspace.dsl \
  -format plantuml/structurizr \
  -output .state/c4-render

shopt -s nullglob
sources=("$build_dir"/*.puml)
shopt -u nullglob
diagram_sources=()
for source in "${sources[@]}"; do
  [[ "$source" == *-key.puml ]] || diagram_sources+=("$source")
done
[[ ${#diagram_sources[@]} -eq 2 ]] || {
  printf 'Expected two exported diagram files, found %s.\n' "${#diagram_sources[@]}" >&2
  exit 1
}

source_names=()
for source in "${diagram_sources[@]}"; do
  source_names+=("$(basename "$source")")
done

docker run --rm \
  --user "$(id -u):$(id -g)" \
  --env PLANTUML_LIMIT_SIZE=8192 \
  --volume "$build_dir:/data" \
  "$plantuml_image" -tpng "${source_names[@]}"

context_png=$(find "$build_dir" -maxdepth 1 -type f -name '*context.png' -print -quit)
containers_png=$(find "$build_dir" -maxdepth 1 -type f -name '*containers.png' -print -quit)
[[ -n "$context_png" && -n "$containers_png" ]] || {
  printf 'Rendered context or container PNG was not found.\n' >&2
  exit 1
}

if ((check_only == 1)); then
  cmp -s "$context_png" "$output_dir/context.png" || {
    printf 'docs/c4/context.png is stale; run make diagrams.\n' >&2
    exit 1
  }
  cmp -s "$containers_png" "$output_dir/containers.png" || {
    printf 'docs/c4/containers.png is stale; run make diagrams.\n' >&2
    exit 1
  }
  printf 'C4 diagrams are current.\n'
else
  install -m 0644 "$context_png" "$output_dir/context.png"
  install -m 0644 "$containers_png" "$output_dir/containers.png"
  printf 'Rendered C4 diagrams in %s.\n' "$output_dir"
fi
