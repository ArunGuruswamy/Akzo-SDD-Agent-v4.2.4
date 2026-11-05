using System.Security.Cryptography;

namespace Akzo.ArchitectureAnalyzer;

internal static class Compatibility
{
    internal static string Hash(byte[] bytes)
    {
        using var sha = SHA256.Create();
        return BitConverter.ToString(sha.ComputeHash(bytes)).Replace("-", "");
    }

    internal static string[] SplitTrim(string value, char separator) =>
        value.Split(new[] { separator }, StringSplitOptions.RemoveEmptyEntries).Select(s => s.Trim()).Where(s => s.Length != 0).ToArray();

#if NETFRAMEWORK
    internal static TValue? GetValueOrDefault<TKey, TValue>(this IDictionary<TKey, TValue> map, TKey key) =>
        map.TryGetValue(key, out var value) ? value : default;
    internal static bool TryAdd<TKey, TValue>(this IDictionary<TKey, TValue> map, TKey key, TValue value)
    {
        if (map.ContainsKey(key)) return false;
        map.Add(key, value);
        return true;
    }
    internal static HashSet<T> ToHashSet<T>(this IEnumerable<T> source) => new(source);
    internal static bool Contains(this string value, string search, StringComparison comparison) => value.IndexOf(search, comparison) >= 0;
#endif
}
