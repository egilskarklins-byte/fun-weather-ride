import 'package:shared_preferences/shared_preferences.dart';
import '../models/project.dart';

class ProjectStorageService {
  static const _key = 'saved_projects_v1';

  Future<List<Project>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.trim().isEmpty) return [];
    try {
      return Project.decodeList(raw);
    } catch (_) {
      return [];
    }
  }

  Future<void> saveAll(List<Project> projects) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, Project.encodeList(projects));
  }

  Future<void> upsert(Project p) async {
    final all = await load();
    final idx = all.indexWhere((x) => x.id == p.id);
    if (idx >= 0) {
      all[idx] = p;
    } else {
      all.add(p);
    }
    await saveAll(all);
  }

  Future<void> deleteById(String id) async {
    final all = await load();
    all.removeWhere((p) => p.id == id);
    await saveAll(all);
  }
}
