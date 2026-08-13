#include <chrono>
#include <cstdio>
#include <cstring>
#include <string>
#include <unordered_set>
#include <vector>

#include "JSONParsingHelper.hpp"
#include "JSONLinesParsingHelper.hpp"
#include "GMLParsingHelper.hpp"

static bool endsWith(const std::string &s, const char *suffix) {
  size_t n = strlen(suffix);
  return s.size() >= n && s.compare(s.size() - n, n, suffix) == 0;
}

long long roundCoordinate(double coord) {
  return static_cast<long long>(llround(coord * 1e9));
}

struct PointKey {
  long long x, y, z;
  bool operator==(const PointKey &o) const { return x == o.x && y == o.y && z == o.z; }
};

struct PointKeyHasher {
  std::size_t operator()(const PointKey &key) const {
    std::size_t hx = std::hash<long long>{}(key.x);
    std::size_t hy = std::hash<long long>{}(key.y);
    std::size_t hz = std::hash<long long>{}(key.z);
    return hx ^ (hy << 1) ^ (hz << 2);
  }
};

struct EdgeKey {
  PointKey points[2];
  bool operator==(const EdgeKey &o) const { return points[0] == o.points[0] && points[1] == o.points[1]; }
};

struct EdgeKeyHasher {
  std::size_t operator()(const EdgeKey &key) const {
    std::uint64_t hash = 1469598103934665603ULL;
    for (int i = 0; i < 2; ++i) {
      hash ^= static_cast<std::uint64_t>(key.points[i].x); hash *= 1099511628211ULL;
      hash ^= static_cast<std::uint64_t>(key.points[i].y); hash *= 1099511628211ULL;
      hash ^= static_cast<std::uint64_t>(key.points[i].z); hash *= 1099511628211ULL;
    }
    return static_cast<std::size_t>(hash);
  }
};

PointKey makePointKey(const AzulPoint &p) {
  return PointKey{roundCoordinate(p.coordinates[0]), roundCoordinate(p.coordinates[1]), roundCoordinate(p.coordinates[2])};
}

bool pointKeyLess(const PointKey &a, const PointKey &b) {
  if (a.x < b.x) return true;
  if (a.x > b.x) return false;
  if (a.y < b.y) return true;
  if (a.y > b.y) return false;
  return a.z < b.z;
}

// Replicates DataManager::generateEdgesForObject scope logic: dedup set is
// shared by a feature subtree; reset at direct file children and "LoD" nodes.
void dedupWalk(const AzulObject &obj, std::unordered_set<EdgeKey, EdgeKeyHasher> &shared,
               bool isFileChild, unsigned long long &raw, unsigned long long &deduped,
               std::unordered_set<EdgeKey, EdgeKeyHasher> &allRawKeys) {
  std::unordered_set<EdgeKey, EdgeKeyHasher> local;
  std::unordered_set<EdgeKey, EdgeKeyHasher> *eff = &shared;
  if (isFileChild || obj.type == "LoD") eff = &local;
  for (const auto &c : obj.children) dedupWalk(c, *eff, false, raw, deduped, allRawKeys);

  for (const auto &poly : obj.polygons) {
    if (poly.exteriorRing.points.size() < 4) continue;
    const auto &pts = poly.exteriorRing.points;
    for (size_t i = 0; i + 1 < pts.size(); ++i) {
      ++raw;
      EdgeKey key;
      PointKey a = makePointKey(pts[i]), b = makePointKey(pts[i + 1]);
      if (pointKeyLess(a, b)) { key.points[0] = a; key.points[1] = b; }
      else { key.points[0] = b; key.points[1] = a; }
      allRawKeys.insert(key);
      if (eff->insert(key).second) ++deduped;
    }
  }
}

int main(int argc, char **argv) {
  if (argc < 2) { fprintf(stderr, "usage: %s <file>\n", argv[0]); return 1; }
  std::string filePath = argv[1];

  AzulObject obj;
  if (endsWith(filePath, ".jsonl")) {
    JSONLinesParsingHelper helper;
    helper.parse(filePath.c_str(), obj);
  } else if (endsWith(filePath, ".gml") || endsWith(filePath, ".xml")) {
    GMLParsingHelper helper;
    helper.parse(filePath.c_str(), obj);
  } else {
    JSONParsingHelper helper;
    bool known = endsWith(filePath, ".city.json") || endsWith(filePath, ".cityjson");
    helper.parse(filePath.c_str(), obj, known);
  }

  std::unordered_set<EdgeKey, EdgeKeyHasher> shared, allRaw;
  unsigned long long raw = 0, deduped = 0;
  dedupWalk(obj, shared, false, raw, deduped, allRaw);

  // Verify: every deduped edge is present in the raw set (nothing lost).
  // We rebuild the deduped set via the same walk and check subset.
  std::unordered_set<EdgeKey, EdgeKeyHasher> shared2, dedupedSet;
  unsigned long long raw2 = 0, deduped2 = 0;
  dedupWalk(obj, shared2, false, raw2, deduped2, dedupedSet);

  bool subsetOk = true;
  for (const auto &k : dedupedSet) {
    if (allRaw.find(k) == allRaw.end()) { subsetOk = false; break; }
  }
  bool allUnique = (dedupedSet.size() == deduped2) && (deduped2 == deduped);

  printf("FILE %s\n", filePath.c_str());
  printf("RAW_SEGMENTS %llu\n", raw);
  printf("UNIQUE_RAW_KEYS %zu\n", allRaw.size());
  printf("DEDUPED_EDGES %llu\n", deduped);
  printf("DEDUPED_UNIQUE %zu\n", dedupedSet.size());
  printf("SUBSET_OK %s\n", subsetOk ? "yes" : "NO");
  printf("COUNTS_CONSISTENT %s\n", allUnique ? "yes" : "NO");
  double reduction = 100.0 * (1.0 - static_cast<double>(deduped) / static_cast<double>(raw));
  printf("REDUCTION_PCT %.1f\n", reduction);
  return (subsetOk && allUnique) ? 0 : 1;
}
