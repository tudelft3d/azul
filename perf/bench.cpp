#include <chrono>
#include <cstdio>
#include <cstring>
#include <string>
#include <sys/resource.h>
#include <sys/time.h>

#include "JSONParsingHelper.hpp"
#include "JSONLinesParsingHelper.hpp"

static bool endsWith(const std::string &s, const char *suffix) {
  size_t n = strlen(suffix);
  return s.size() >= n && s.compare(s.size() - n, n, suffix) == 0;
}

static void countObject(const AzulObject &obj, unsigned long long &children,
                        unsigned long long &polygons, unsigned long long &ringPoints,
                        unsigned long long &styles, unsigned long long &themes,
                        unsigned long long &attributes) {
  ++children;
  polygons += obj.polygons.size();
  styles += obj.appearanceStyles.size();
  themes += obj.appearanceThemes.size();
  attributes += obj.attributes.size();
  for (const auto &p : obj.polygons) {
    ringPoints += p.exteriorRing.points.size();
    for (const auto &r : p.interiorRings) ringPoints += r.points.size();
  }
  for (const auto &c : obj.children) countObject(c, children, polygons, ringPoints, styles, themes, attributes);
}

int main(int argc, char **argv) {
  if (argc < 2) {
    fprintf(stderr, "usage: %s <file>\n", argv[0]);
    return 1;
  }
  std::string filePath = argv[1];

  unsigned long long children = 0, polygons = 0, ringPoints = 0, styles = 0, themes = 0, attributes = 0;

  auto t0 = std::chrono::high_resolution_clock::now();
  if (endsWith(filePath, ".jsonl")) {
    JSONLinesParsingHelper helper;
    AzulObject obj;
    helper.parse(filePath.c_str(), obj);
    auto t1 = std::chrono::high_resolution_clock::now();
    countObject(obj, children, polygons, ringPoints, styles, themes, attributes);
    double ms = std::chrono::duration<double, std::milli>(t1 - t0).count();
    printf("PARSE_MS %.1f\n", ms);
  } else if (endsWith(filePath, ".city.json") || endsWith(filePath, ".cityjson")) {
    JSONParsingHelper helper;
    AzulObject obj;
    helper.parse(filePath.c_str(), obj, true);
    auto t1 = std::chrono::high_resolution_clock::now();
    countObject(obj, children, polygons, ringPoints, styles, themes, attributes);
    double ms = std::chrono::duration<double, std::milli>(t1 - t0).count();
    printf("PARSE_MS %.1f\n", ms);
  } else if (endsWith(filePath, ".json")) {
    JSONParsingHelper helper;
    AzulObject obj;
    helper.parse(filePath.c_str(), obj, false);
    auto t1 = std::chrono::high_resolution_clock::now();
    countObject(obj, children, polygons, ringPoints, styles, themes, attributes);
    double ms = std::chrono::duration<double, std::milli>(t1 - t0).count();
    printf("PARSE_MS %.1f\n", ms);
  } else {
    fprintf(stderr, "unsupported extension\n");
    return 1;
  }

  struct rusage usage;
  getrusage(RUSAGE_SELF, &usage);
  printf("PEAK_RSS_MB %.1f\n", usage.ru_maxrss / (1024.0 * 1024.0));
  printf("CHILDREN %llu\n", children);
  printf("POLYGONS %llu\n", polygons);
  printf("RING_POINTS %llu\n", ringPoints);
  printf("STYLES %llu\n", styles);
  printf("THEMES %llu\n", themes);
  printf("ATTRIBUTES %llu\n", attributes);
  return 0;
}
