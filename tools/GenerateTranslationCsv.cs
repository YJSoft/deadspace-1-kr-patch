using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Text;
using System.Xml;

internal static class GenerateTranslationCsv
{
    private sealed class Lh2Entry
    {
        public uint Id;
        public string English;
    }

    private static uint ReadU32(byte[] data, int offset)
    {
        return (uint)(data[offset] |
                      (data[offset + 1] << 8) |
                      (data[offset + 2] << 16) |
                      (data[offset + 3] << 24));
    }

    private static List<Lh2Entry> ReadLh2(
        string path,
        out int totalCount,
        out int recoveredNbspCount,
        out int invalidUtf8Count,
        out int singleCharacterCount,
        out int nonMeaningfulCount)
    {
        byte[] data = File.ReadAllBytes(path);
        if (data.Length < 32 || Encoding.ASCII.GetString(data, 0, 4) != "LCH2")
        {
            throw new InvalidDataException("The source localization file is not LCH2.");
        }

        int count = checked((int)ReadU32(data, 16));
        totalCount = count;
        recoveredNbspCount = 0;
        invalidUtf8Count = 0;
        singleCharacterCount = 0;
        nonMeaningfulCount = 0;
        int idsOffset = 32;
        int offsetsOffset = checked(idsOffset + count * 4);
        if (offsetsOffset + count * 4 > data.Length)
        {
            throw new InvalidDataException("The LCH2 index is outside the file.");
        }

        var entries = new List<Lh2Entry>(count);
        var ids = new HashSet<uint>();
        var strictUtf8 = new UTF8Encoding(false, true);
        for (int index = 0; index < count; ++index)
        {
            uint id = ReadU32(data, idsOffset + index * 4);
            int stringOffset = checked((int)ReadU32(data, offsetsOffset + index * 4));
            if (stringOffset < 0 || stringOffset >= data.Length)
            {
                throw new InvalidDataException("Invalid LCH2 string offset for 0x" + id.ToString("X8"));
            }

            int end = Array.IndexOf(data, (byte)0, stringOffset);
            if (end < 0)
            {
                throw new InvalidDataException("Unterminated LCH2 string for 0x" + id.ToString("X8"));
            }
            if (!ids.Add(id))
            {
                throw new InvalidDataException("Duplicate LCH2 ID: 0x" + id.ToString("X8"));
            }

            string english;
            try
            {
                english = strictUtf8.GetString(data, stringOffset, end - stringOffset);
            }
            catch (DecoderFallbackException)
            {
                // A small set of otherwise-ASCII English strings uses the
                // Windows-1252 0xA0 byte as a non-breaking space. Normalize
                // only that byte and require the result to be valid UTF-8.
                // This recovers the affected audio-log subtitles without
                // importing unrelated CP1251/CP1252 text as mojibake.
                byte[] normalized = new byte[end - stringOffset];
                Buffer.BlockCopy(data, stringOffset, normalized, 0, normalized.Length);
                bool replacedNbsp = false;
                for (int byteIndex = 0; byteIndex < normalized.Length; ++byteIndex)
                {
                    if (normalized[byteIndex] == 0xA0)
                    {
                        normalized[byteIndex] = 0x20;
                        replacedNbsp = true;
                    }
                }

                if (!replacedNbsp)
                {
                    ++invalidUtf8Count;
                    continue;
                }

                try
                {
                    english = strictUtf8.GetString(normalized);
                    ++recoveredNbspCount;
                }
                catch (DecoderFallbackException)
                {
                    ++invalidUtf8Count;
                    continue;
                }
            }

            // Keep the reference column easy to edit and compare. The game
            // uses 0xA0 together with an ordinary space in several sentences;
            // retain the spacing but represent it with portable ASCII spaces.
            english = english.Replace('\u00A0', ' ');

            string trimmed = english.Trim();
            if (trimmed.Length <= 1)
            {
                ++singleCharacterCount;
                continue;
            }

            bool hasLetterOrDigit = false;
            foreach (char character in trimmed)
            {
                if (Char.IsLetterOrDigit(character))
                {
                    hasLetterOrDigit = true;
                    break;
                }
            }
            if (!hasLetterOrDigit)
            {
                ++nonMeaningfulCount;
                continue;
            }

            entries.Add(new Lh2Entry
            {
                Id = id,
                English = english,
            });
        }
        return entries;
    }

    private static List<string[]> ReadCsvRecords(string path)
    {
        string text = File.ReadAllText(path, Encoding.UTF8);
        var records = new List<string[]>();
        var record = new List<string>();
        var field = new StringBuilder();
        bool quoted = false;

        for (int index = 0; index < text.Length; ++index)
        {
            char character = text[index];
            if (quoted)
            {
                if (character == '"')
                {
                    if (index + 1 < text.Length && text[index + 1] == '"')
                    {
                        field.Append('"');
                        ++index;
                    }
                    else
                    {
                        quoted = false;
                    }
                }
                else
                {
                    field.Append(character);
                }
                continue;
            }

            if (character == '"' && field.Length == 0)
            {
                quoted = true;
            }
            else if (character == ',')
            {
                record.Add(field.ToString());
                field.Clear();
            }
            else if (character == '\r' || character == '\n')
            {
                if (character == '\r' && index + 1 < text.Length && text[index + 1] == '\n')
                {
                    ++index;
                }
                record.Add(field.ToString());
                field.Clear();
                records.Add(record.ToArray());
                record.Clear();
            }
            else
            {
                field.Append(character);
            }
        }

        if (quoted)
        {
            throw new InvalidDataException("Unterminated quoted CSV field.");
        }
        if (field.Length > 0 || record.Count > 0)
        {
            record.Add(field.ToString());
            records.Add(record.ToArray());
        }
        return records;
    }

    private static uint ParseTranslationId(string text)
    {
        string value = text.Trim();
        if (value.StartsWith("0x", StringComparison.OrdinalIgnoreCase))
        {
            return uint.Parse(value.Substring(2), NumberStyles.HexNumber, CultureInfo.InvariantCulture);
        }
        return uint.Parse(value, NumberStyles.Integer, CultureInfo.InvariantCulture);
    }

    private static Dictionary<uint, string> ReadExistingTranslations(string path)
    {
        List<string[]> records = ReadCsvRecords(path);
        if (records.Count == 0 ||
            records[0].Length != 3 ||
            !String.Equals(records[0][0].TrimStart('\uFEFF'), "id", StringComparison.OrdinalIgnoreCase) ||
            !String.Equals(records[0][1], "english", StringComparison.OrdinalIgnoreCase) ||
            !String.Equals(records[0][2], "translation", StringComparison.OrdinalIgnoreCase))
        {
            throw new InvalidDataException("Existing CSV header must be: id,english,translation");
        }

        var translations = new Dictionary<uint, string>();
        for (int row = 1; row < records.Count; ++row)
        {
            string[] fields = records[row];
            if (fields.Length == 1 && fields[0].Length == 0)
            {
                continue;
            }
            if (fields.Length != 3)
            {
                throw new InvalidDataException(
                    "Existing CSV row " + (row + 1) + " must contain exactly 3 fields.");
            }

            uint id = ParseTranslationId(fields[0]);
            if (fields[2].Length == 0)
            {
                throw new InvalidDataException(
                    "Empty existing translation for 0x" + id.ToString("X8"));
            }
            if (translations.ContainsKey(id))
            {
                throw new InvalidDataException(
                    "Duplicate existing translation ID: 0x" + id.ToString("X8"));
            }
            translations.Add(id, fields[2]);
        }
        return translations;
    }

    private static string NormalizeTranslationWhitespace(string value)
    {
        var normalized = new StringBuilder(value.Length);
        bool previousWasSpace = false;
        foreach (char character in value)
        {
            if (character == ' ' || character == '\t' || character == '\u3000')
            {
                if (!previousWasSpace)
                {
                    normalized.Append(' ');
                    previousWasSpace = true;
                }
            }
            else
            {
                normalized.Append(character);
                previousWasSpace = false;
            }
        }
        return normalized.ToString().Trim(' ');
    }

    private static Dictionary<string, string> ReadLegacyTranslations(
        string launcherXmlPath,
        out int pairCount,
        out int conflictCount)
    {
        var document = new XmlDocument();
        document.PreserveWhitespace = true;
        document.Load(launcherXmlPath);

        var translations = new Dictionary<string, string>(StringComparer.Ordinal);
        pairCount = 0;
        conflictCount = 0;

        XmlNodeList nodes = document.SelectNodes("//Translation//String[English and Chinese]");
        foreach (XmlNode node in nodes)
        {
            XmlNode englishNode = node.SelectSingleNode("./English");
            XmlNode koreanNode = node.SelectSingleNode("./Chinese");
            if (englishNode == null || koreanNode == null)
            {
                continue;
            }

            string english = englishNode.InnerText;
            string korean = NormalizeTranslationWhitespace(koreanNode.InnerText);
            ++pairCount;

            string existing;
            if (!translations.TryGetValue(english, out existing))
            {
                translations.Add(english, korean);
            }
            else if (!String.Equals(existing, korean, StringComparison.Ordinal))
            {
                // The legacy runtime patch could only identify strings by their
                // English contents, so retain its first definition deterministically.
                ++conflictCount;
            }
        }
        return translations;
    }

    private static string CsvField(string value)
    {
        return "\"" + value.Replace("\"", "\"\"") + "\"";
    }

    private static string NormalizeEnglishForFallback(string value)
    {
        var normalized = new StringBuilder(value.Length);
        foreach (char character in value)
        {
            if (!Char.IsWhiteSpace(character))
            {
                normalized.Append(character);
            }
        }
        return normalized.ToString();
    }

    private static Dictionary<string, string> BuildWhitespaceInsensitiveIndex(
        IDictionary<string, string> translations,
        out int ambiguousCount)
    {
        var normalized = new Dictionary<string, string>(StringComparer.Ordinal);
        var ambiguous = new HashSet<string>(StringComparer.Ordinal);

        foreach (KeyValuePair<string, string> pair in translations)
        {
            string key = NormalizeEnglishForFallback(pair.Key);
            string existing;
            if (!normalized.TryGetValue(key, out existing))
            {
                normalized.Add(key, pair.Value);
            }
            else if (!String.Equals(existing, pair.Value, StringComparison.Ordinal))
            {
                ambiguous.Add(key);
            }
        }

        foreach (string key in ambiguous)
        {
            normalized.Remove(key);
        }
        ambiguousCount = ambiguous.Count;
        return normalized;
    }

    private static void WriteCsv(
        string path,
        IList<Lh2Entry> entries,
        IDictionary<uint, string> existingTranslations,
        IDictionary<string, string> legacyTranslations,
        IDictionary<string, string> whitespaceInsensitiveTranslations,
        out int preservedCount,
        out int translatedCount,
        out int fallbackCount,
        out int missingCount)
    {
        preservedCount = 0;
        translatedCount = 0;
        fallbackCount = 0;
        missingCount = 0;
        Directory.CreateDirectory(Path.GetDirectoryName(Path.GetFullPath(path)));

        using (var writer = new StreamWriter(path, false, new UTF8Encoding(true)))
        {
            writer.NewLine = "\r\n";
            writer.WriteLine("id,english,translation");

            foreach (Lh2Entry entry in entries)
            {
                string translation;
                if (existingTranslations != null &&
                    existingTranslations.TryGetValue(entry.Id, out translation))
                {
                    ++preservedCount;
                }
                else if (legacyTranslations.TryGetValue(entry.English, out translation))
                {
                    ++translatedCount;
                }
                else if (whitespaceInsensitiveTranslations.TryGetValue(
                    NormalizeEnglishForFallback(entry.English),
                    out translation))
                {
                    ++translatedCount;
                    ++fallbackCount;
                }
                else
                {
                    translation = "< 번역 누락 : 0x" + entry.Id.ToString("X8") + " >";
                    ++missingCount;
                }

                writer.Write("0x");
                writer.Write(entry.Id.ToString("X8"));
                writer.Write(',');
                writer.Write(CsvField(entry.English));
                writer.Write(',');
                writer.WriteLine(CsvField(translation));
            }
        }
    }

    public static int Main(string[] args)
    {
        if (args.Length != 3 && args.Length != 4)
        {
            Console.Error.WriteLine(
                "Usage: GenerateTranslationCsv <original-lh2> <legacy-launcher.xml> <output.csv> [existing.csv]");
            return 2;
        }

        try
        {
            int totalCount;
            int recoveredNbspCount;
            int invalidUtf8Count;
            int singleCharacterCount;
            int nonMeaningfulCount;
            List<Lh2Entry> entries = ReadLh2(
                args[0],
                out totalCount,
                out recoveredNbspCount,
                out invalidUtf8Count,
                out singleCharacterCount,
                out nonMeaningfulCount);
            Dictionary<uint, string> existingTranslations =
                args.Length == 4 ? ReadExistingTranslations(args[3]) : null;
            int pairCount;
            int conflictCount;
            Dictionary<string, string> legacyTranslations = ReadLegacyTranslations(
                args[1],
                out pairCount,
                out conflictCount);
            int ambiguousNormalizedCount;
            Dictionary<string, string> whitespaceInsensitiveTranslations =
                BuildWhitespaceInsensitiveIndex(
                    legacyTranslations,
                    out ambiguousNormalizedCount);

            int preservedCount;
            int translatedCount;
            int fallbackCount;
            int missingCount;
            WriteCsv(
                args[2],
                entries,
                existingTranslations,
                legacyTranslations,
                whitespaceInsensitiveTranslations,
                out preservedCount,
                out translatedCount,
                out fallbackCount,
                out missingCount);

            Console.WriteLine("LCH2 IDs: {0}", totalCount);
            Console.WriteLine("CSV-eligible IDs: {0}", entries.Count);
            Console.WriteLine(
                "Windows-1252 NBSP strings recovered: {0}",
                recoveredNbspCount);
            Console.WriteLine("Excluded invalid UTF-8: {0}", invalidUtf8Count);
            Console.WriteLine("Excluded single-character strings: {0}", singleCharacterCount);
            Console.WriteLine("Excluded non-meaningful strings: {0}", nonMeaningfulCount);
            Console.WriteLine(
                "Existing translations preserved by ID: {0}",
                preservedCount);
            Console.WriteLine("Legacy XML pairs: {0}", pairCount);
            Console.WriteLine("Unique English keys: {0}", legacyTranslations.Count);
            Console.WriteLine("Conflicting duplicate keys (first kept): {0}", conflictCount);
            Console.WriteLine(
                "Ambiguous whitespace-insensitive keys (fallback disabled): {0}",
                ambiguousNormalizedCount);
            Console.WriteLine("Translated IDs: {0}", translatedCount);
            Console.WriteLine("Whitespace-only fallback matches: {0}", fallbackCount);
            Console.WriteLine("Missing placeholders: {0}", missingCount);
            Console.WriteLine("Wrote: {0}", Path.GetFullPath(args[2]));
            return 0;
        }
        catch (Exception exception)
        {
            Console.Error.WriteLine(exception);
            return 1;
        }
    }
}
