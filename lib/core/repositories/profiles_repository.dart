import '../models/profile.dart';
import '../supabase/supabase_client.dart';
import '../errors/failures.dart';

/// Repository that manages data retrieval and updates for the `profiles` table.
class ProfilesRepository {
  final _client = SupabaseService.client;

  /// Retrieves the profile associated with the given [id].
  /// Throws a [Failure] if the fetch fails or if blocked by RLS.
  Future<Profile> getProfile(String id) async {
    try {
      final response = await _client
          .from('profiles')
          .select()
          .eq('id', id)
          .single();
      return Profile.fromJson(response);
    } catch (e) {
      throw FailureMapper.fromException(e);
    }
  }

  /// Updates the profile data. Respects role protections in the database.
  /// Throws a [Failure] on error.
  Future<Profile> updateProfile(Profile profile) async {
    try {
      final response = await _client
          .from('profiles')
          .update(profile.toJson())
          .eq('id', profile.id)
          .select()
          .single();
      return Profile.fromJson(response);
    } catch (e) {
      throw FailureMapper.fromException(e);
    }
  }
}
