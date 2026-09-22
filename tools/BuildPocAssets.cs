using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.Drawing.Text;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Runtime.InteropServices;
using System.Text;

internal static class BuildPocAssets
{
    private const int AtlasWidth = 2048;
    private const int AtlasHeight = 1024;
    private const int MipCount = 10;
    private const int Dxt5 = 1 << 2;
    private const int WeightColourByAlpha = 1 << 7;
    private const int ColourIterativeClusterFit = 1 << 8;

    [DllImport("squish64.dll", EntryPoint = "DecompressImage", CallingConvention = CallingConvention.Cdecl)]
    private static extern void DecompressImage(
        byte[] rgba,
        int width,
        int height,
        byte[] blocks,
        int flags);

    [DllImport("squish64.dll", EntryPoint = "CompressImage", CallingConvention = CallingConvention.Cdecl)]
    private static extern void CompressImage(
        byte[] rgba,
        int width,
        int height,
        byte[] blocks,
        int flags,
        float[] metric);

    private sealed class FontAsset
    {
        public string Inf;
        public string Tg4h;
        public string Tg4d;
        public string EmbeddedName;
        public ushort GlyphWidth;
        public ushort GlyphHeight;
        public float GlyphEmSize;

        public FontAsset(
            string inf,
            string tg4h,
            string tg4d,
            string embeddedName,
            ushort glyphWidth,
            ushort glyphHeight,
            float glyphEmSize)
        {
            Inf = inf;
            Tg4h = tg4h;
            Tg4d = tg4d;
            EmbeddedName = embeddedName;
            GlyphWidth = glyphWidth;
            GlyphHeight = glyphHeight;
            GlyphEmSize = glyphEmSize;
        }
    }

    private sealed class AtlasPacker
    {
        private const int Gutter = 5;
        private int x = Gutter;
        private int y = Gutter;
        private int rowHeight;

        public Rectangle Allocate(int width, int height)
        {
            if (width <= 0 || height <= 0 ||
                width + Gutter * 2 > AtlasWidth ||
                height + Gutter * 2 > AtlasHeight)
            {
                throw new InvalidDataException("Invalid glyph dimensions for atlas packing.");
            }

            if (x + width + Gutter > AtlasWidth)
            {
                x = Gutter;
                y += rowHeight + Gutter * 2;
                rowHeight = 0;
            }
            if (y + height + Gutter > AtlasHeight)
            {
                throw new InvalidDataException("The rebuilt font atlas is full.");
            }

            var result = new Rectangle(x, y, width, height);
            x += width + Gutter * 2;
            rowHeight = Math.Max(rowHeight, height);
            return result;
        }
    }

    private sealed class TranslationEntry
    {
        public string English;
        public string Translation;
    }

    private static ushort ReadU16(byte[] data, int offset)
    {
        return (ushort)(data[offset] | (data[offset + 1] << 8));
    }

    private static uint ReadU32(byte[] data, int offset)
    {
        return (uint)(data[offset] |
                      (data[offset + 1] << 8) |
                      (data[offset + 2] << 16) |
                      (data[offset + 3] << 24));
    }

    private static void WriteU16(byte[] data, int offset, ushort value)
    {
        data[offset] = (byte)value;
        data[offset + 1] = (byte)(value >> 8);
    }

    private static void WriteU32(byte[] data, int offset, uint value)
    {
        data[offset] = (byte)value;
        data[offset + 1] = (byte)(value >> 8);
        data[offset + 2] = (byte)(value >> 16);
        data[offset + 3] = (byte)(value >> 24);
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

    private static Dictionary<uint, TranslationEntry> LoadTranslations(string path)
    {
        List<string[]> records = ReadCsvRecords(path);
        if (records.Count == 0 ||
            records[0].Length != 3 ||
            !String.Equals(records[0][0].TrimStart('\uFEFF'), "id", StringComparison.OrdinalIgnoreCase) ||
            !String.Equals(records[0][1], "english", StringComparison.OrdinalIgnoreCase) ||
            !String.Equals(records[0][2], "translation", StringComparison.OrdinalIgnoreCase))
        {
            throw new InvalidDataException("CSV header must be: id,english,translation");
        }

        var translations = new Dictionary<uint, TranslationEntry>();
        for (int row = 1; row < records.Count; ++row)
        {
            string[] fields = records[row];
            if (fields.Length == 1 && fields[0].Length == 0)
            {
                continue;
            }
            if (fields.Length != 3)
            {
                throw new InvalidDataException("CSV row " + (row + 1) + " must contain exactly 3 fields.");
            }

            uint id = ParseTranslationId(fields[0]);
            if (fields[2].Length == 0)
            {
                throw new InvalidDataException("Empty translation for 0x" + id.ToString("X8"));
            }
            if (translations.ContainsKey(id))
            {
                throw new InvalidDataException("Duplicate translation ID: 0x" + id.ToString("X8"));
            }

            translations.Add(id, new TranslationEntry
            {
                English = fields[1],
                Translation = fields[2],
            });
        }
        return translations;
    }

    private static List<ushort> CollectHangulCodepoints(
        IDictionary<uint, TranslationEntry> translations)
    {
        return translations.Values
            .SelectMany(value => value.Translation)
            .Where(character => character > 0x7F &&
                                !Char.IsControl(character) &&
                                !Char.IsSurrogate(character))
            .Distinct()
            .OrderBy(character => character)
            .Select(character => (ushort)character)
            .ToList();
    }

    private static void PatchLh2(
        string sourcePath,
        string destinationPath,
        IDictionary<uint, TranslationEntry> translations)
    {
        byte[] source = File.ReadAllBytes(sourcePath);
        if (Encoding.ASCII.GetString(source, 0, 4) != "LCH2")
        {
            throw new InvalidDataException("The source localization file is not LCH2.");
        }

        int count = checked((int)ReadU32(source, 16));
        int idsOffset = 32;
        int offsetsOffset = idsOffset + count * 4;

        uint[] ids = new uint[count];
        byte[][] strings = new byte[count][];
        int replaced = 0;
        int englishMismatches = 0;

        for (int index = 0; index < count; ++index)
        {
            ids[index] = ReadU32(source, idsOffset + index * 4);
            int stringOffset = checked((int)ReadU32(source, offsetsOffset + index * 4));
            int end = Array.IndexOf(source, (byte)0, stringOffset);
            if (end < 0)
            {
                throw new InvalidDataException("Unterminated LCH2 string.");
            }

            TranslationEntry entry;
            if (translations.TryGetValue(ids[index], out entry))
            {
                string sourceEnglish = Encoding.UTF8.GetString(source, stringOffset, end - stringOffset);
                if (!String.Equals(sourceEnglish, entry.English, StringComparison.Ordinal))
                {
                    ++englishMismatches;
                }
                strings[index] = Encoding.UTF8.GetBytes(entry.Translation);
                ++replaced;
            }
            else
            {
                int length = end - stringOffset;
                strings[index] = new byte[length];
                Buffer.BlockCopy(source, stringOffset, strings[index], 0, length);
            }
        }

        if (replaced != translations.Count)
        {
            throw new InvalidDataException(
                "CSV/LCH2 ID mismatch: replaced " + replaced +
                ", CSV rows " + translations.Count +
                ", LCH2 IDs " + count + ".");
        }

        using (var output = new MemoryStream())
        using (var writer = new BinaryWriter(output))
        {
            writer.Write(source, 0, 32);
            for (int index = 0; index < count; ++index)
            {
                writer.Write(ids[index]);
            }

            long offsetsPosition = output.Position;
            writer.Write(new byte[count * 4]);
            uint[] offsets = new uint[count];

            for (int index = 0; index < count; ++index)
            {
                offsets[index] = checked((uint)output.Position);
                writer.Write(strings[index]);
                writer.Write((byte)0);
            }

            byte[] result = output.ToArray();
            WriteU32(result, 4, checked((uint)result.Length));
            for (int index = 0; index < count; ++index)
            {
                WriteU32(result, checked((int)offsetsPosition) + index * 4, offsets[index]);
            }

            Directory.CreateDirectory(Path.GetDirectoryName(destinationPath));
            File.WriteAllBytes(destinationPath, result);
            Console.WriteLine(
                "LCH2: replaced {0} localized strings, {1} -> {2} bytes",
                replaced,
                source.Length,
                result.Length);
            Console.WriteLine(
                "LCH2: preserved {0} excluded source strings",
                count - replaced);
            Console.WriteLine("LCH2: English reference mismatches: {0}", englishMismatches);
        }
    }

    private static Bitmap RgbaToBitmap(byte[] rgba, int width, int height)
    {
        var bitmap = new Bitmap(width, height, PixelFormat.Format32bppArgb);
        var area = new Rectangle(0, 0, width, height);
        BitmapData locked = bitmap.LockBits(area, ImageLockMode.WriteOnly, bitmap.PixelFormat);
        try
        {
            byte[] bgra = new byte[rgba.Length];
            for (int offset = 0; offset < rgba.Length; offset += 4)
            {
                bgra[offset + 0] = rgba[offset + 2];
                bgra[offset + 1] = rgba[offset + 1];
                bgra[offset + 2] = rgba[offset + 0];
                bgra[offset + 3] = rgba[offset + 3];
            }
            Marshal.Copy(bgra, 0, locked.Scan0, bgra.Length);
        }
        finally
        {
            bitmap.UnlockBits(locked);
        }
        return bitmap;
    }

    private static byte[] BitmapToRgba(Bitmap bitmap)
    {
        var area = new Rectangle(0, 0, bitmap.Width, bitmap.Height);
        BitmapData locked = bitmap.LockBits(area, ImageLockMode.ReadOnly, PixelFormat.Format32bppArgb);
        try
        {
            int byteCount = bitmap.Width * bitmap.Height * 4;
            byte[] bgra = new byte[byteCount];
            Marshal.Copy(locked.Scan0, bgra, 0, byteCount);
            byte[] rgba = new byte[byteCount];
            for (int offset = 0; offset < byteCount; offset += 4)
            {
                rgba[offset + 0] = bgra[offset + 2];
                rgba[offset + 1] = bgra[offset + 1];
                rgba[offset + 2] = bgra[offset + 0];
                rgba[offset + 3] = bgra[offset + 3];
            }
            return rgba;
        }
        finally
        {
            bitmap.UnlockBits(locked);
        }
    }

    private static Bitmap ResizeBitmap(Bitmap source, int width, int height)
    {
        var result = new Bitmap(width, height, PixelFormat.Format32bppArgb);
        using (Graphics graphics = Graphics.FromImage(result))
        {
            graphics.CompositingMode = CompositingMode.SourceCopy;
            graphics.CompositingQuality = CompositingQuality.HighQuality;
            graphics.InterpolationMode = InterpolationMode.HighQualityBicubic;
            graphics.PixelOffsetMode = PixelOffsetMode.HighQuality;
            graphics.DrawImage(
                source,
                new Rectangle(0, 0, width, height),
                new Rectangle(0, 0, source.Width, source.Height),
                GraphicsUnit.Pixel);
        }
        return result;
    }

    private static float MeasureGlyphAdvance(
        Graphics graphics,
        Font font,
        ushort codepoint)
    {
        string text = codepoint == 0x20
            ? "\u00A0"
            : ((char)codepoint).ToString();
        SizeF measured = graphics.MeasureString(
            text,
            font,
            PointF.Empty,
            StringFormat.GenericTypographic);
        return measured.Width;
    }

    private static GraphicsPath CreatePositionedGlyphPath(
        FontFamily family,
        ushort codepoint,
        FontAsset asset)
    {
        var path = new GraphicsPath();
        path.AddString(
            ((char)codepoint).ToString(),
            family,
            (int)FontStyle.Regular,
            asset.GlyphEmSize,
            PointF.Empty,
            StringFormat.GenericTypographic);

        RectangleF bounds = path.GetBounds();
        if (bounds.Width <= 0.0f || bounds.Height <= 0.0f)
        {
            path.Dispose();
            throw new InvalidDataException(
                "Font produced an empty glyph for U+" + codepoint.ToString("X4"));
        }

        // Keep one shared line box for Latin, Hangul and punctuation. Horizontal
        // centering in a fixed 32 px cell is intentionally not used: the engine
        // advances by the FFN advance field, so centering a narrow glyph such as
        // 'i' in a 32 px quad creates a large false gap before the visible ink.
        float lineHeight = asset.GlyphEmSize *
            family.GetLineSpacing(FontStyle.Regular) /
            family.GetEmHeight(FontStyle.Regular);
        float logicalTop = (asset.GlyphHeight - lineHeight) * 0.5f;
        using (var transform = new Matrix())
        {
            transform.Translate(0.0f, logicalTop, MatrixOrder.Append);
            path.Transform(transform);
        }
        return path;
    }

    private static Rectangle GetGlyphBounds(GraphicsPath path, FontAsset asset, ushort codepoint)
    {
        RectangleF bounds = path.GetBounds();
        var result = Rectangle.FromLTRB(
            (int)Math.Floor(bounds.Left),
            (int)Math.Floor(bounds.Top),
            (int)Math.Ceiling(bounds.Right),
            (int)Math.Ceiling(bounds.Bottom));
        if (result.Width <= 0 || result.Height <= 0 ||
            result.Width > asset.GlyphWidth || result.Height > asset.GlyphHeight)
        {
            throw new InvalidDataException(
                "Font glyph exceeds its logical cell: U+" +
                codepoint.ToString("X4") + " bounds=" + result);
        }
        return result;
    }

    private static void DrawGlyph(
        Graphics graphics,
        GraphicsPath path,
        Rectangle logicalBounds,
        Rectangle atlasRectangle,
        ushort codepoint)
    {
        using (var transform = new Matrix())
        {
            transform.Translate(
                atlasRectangle.Left - logicalBounds.Left,
                atlasRectangle.Top - logicalBounds.Top,
                MatrixOrder.Append);
            path.Transform(transform);
        }

        RectangleF renderedBounds = path.GetBounds();
        if (renderedBounds.Left < atlasRectangle.Left - 0.01f ||
            renderedBounds.Top < atlasRectangle.Top - 0.01f ||
            renderedBounds.Right > atlasRectangle.Right + 0.01f ||
            renderedBounds.Bottom > atlasRectangle.Bottom + 0.01f)
        {
            throw new InvalidDataException(
                "Positioned glyph exceeds its atlas rectangle: U+" +
                codepoint.ToString("X4"));
        }

        using (var brush = new SolidBrush(Color.White))
        {
            graphics.FillPath(brush, path);
        }
    }

    private static Dictionary<ushort, List<int>> IndexGlyphRecords(
        byte[] inf,
        int glyphCount,
        int glyphsOffset)
    {
        var records = new Dictionary<ushort, List<int>>();
        for (int index = 0; index < glyphCount; ++index)
        {
            int record = glyphsOffset + index * 24;
            ushort codepoint = ReadU16(inf, record);
            List<int> matches;
            if (!records.TryGetValue(codepoint, out matches))
            {
                matches = new List<int>();
                records.Add(codepoint, matches);
            }
            matches.Add(record);
        }
        return records;
    }

    private static Rectangle ReadGlyphRectangle(byte[] inf, int record)
    {
        return Rectangle.FromLTRB(
            ReadU16(inf, record + 12) / 16,
            ReadU16(inf, record + 14) / 16,
            ReadU16(inf, record + 16) / 16,
            ReadU16(inf, record + 18) / 16);
    }

    private static void ReplaceEmbeddedFontName(
        byte[] inf,
        string sourceName,
        string destinationName)
    {
        byte[] source = Encoding.ASCII.GetBytes(sourceName + "\0");
        byte[] destination = Encoding.ASCII.GetBytes(destinationName + "\0");
        const int nameFieldLength = 32;
        if (destination.Length > nameFieldLength)
        {
            throw new InvalidDataException("FFN embedded name is too long: " + destinationName);
        }

        int match = -1;
        for (int offset = 0; offset <= inf.Length - source.Length; ++offset)
        {
            bool equal = true;
            for (int index = 0; index < source.Length; ++index)
            {
                if (inf[offset + index] != source[index])
                {
                    equal = false;
                    break;
                }
            }
            if (!equal)
            {
                continue;
            }
            if (match >= 0)
            {
                throw new InvalidDataException(
                    "Multiple embedded FFN names found: " + sourceName);
            }
            match = offset;
        }
        if (match < 0)
        {
            throw new InvalidDataException("Embedded FFN name was not found: " + sourceName);
        }

        Array.Clear(inf, match, nameFieldLength);
        Buffer.BlockCopy(destination, 0, inf, match, destination.Length);
    }

    private static void ExpandFontFromTemplate(
        string workRoot,
        FontAsset template,
        FontAsset target)
    {
        string templateInf = Path.Combine(workRoot, template.Inf);
        string targetInf = Path.Combine(workRoot, target.Inf);
        byte[] expandedInf = File.ReadAllBytes(templateInf);
        ReplaceEmbeddedFontName(
            expandedInf,
            template.EmbeddedName,
            target.EmbeddedName);
        File.WriteAllBytes(targetInf, expandedInf);

        File.Copy(
            Path.Combine(workRoot, template.Tg4h),
            Path.Combine(workRoot, target.Tg4h),
            true);
        File.Copy(
            Path.Combine(workRoot, template.Tg4d),
            Path.Combine(workRoot, target.Tg4d),
            true);

        Console.WriteLine(
            "Font: expanded {0} from the {1} container",
            target.EmbeddedName,
            template.EmbeddedName);
    }

    private static void WriteGlyphRectangle(byte[] inf, int record, Rectangle rectangle)
    {
        WriteU16(inf, record + 12, checked((ushort)(rectangle.Left * 16)));
        WriteU16(inf, record + 14, checked((ushort)(rectangle.Top * 16)));
        WriteU16(inf, record + 16, checked((ushort)(rectangle.Right * 16)));
        WriteU16(inf, record + 18, checked((ushort)(rectangle.Bottom * 16)));
    }

    private static void PatchFont(
        string workRoot,
        string steamRoot,
        FontAsset asset,
        IList<ushort> requestedCodepoints,
        FontFamily family)
    {
        string infPath = Path.Combine(workRoot, asset.Inf);
        string tg4dPath = Path.Combine(workRoot, asset.Tg4d);
        string steamInfPath = Path.Combine(steamRoot, asset.Inf);
        byte[] inf = File.ReadAllBytes(infPath);
        byte[] steamInf = File.ReadAllBytes(steamInfPath);

        int glyphCount = ReadU16(inf, 10);
        int glyphsOffset = checked((int)ReadU32(inf, 12));
        int steamGlyphCount = ReadU16(steamInf, 10);
        int steamGlyphsOffset = checked((int)ReadU32(steamInf, 12));
        if (glyphCount < requestedCodepoints.Count || glyphsOffset + glyphCount * 24 > inf.Length ||
            steamGlyphsOffset + steamGlyphCount * 24 > steamInf.Length)
        {
            throw new InvalidDataException("Invalid or undersized FFN glyph table: " + infPath);
        }

        Dictionary<ushort, List<int>> targetRecords = IndexGlyphRecords(inf, glyphCount, glyphsOffset);
        Dictionary<ushort, List<int>> steamRecords = IndexGlyphRecords(
            steamInf,
            steamGlyphCount,
            steamGlyphsOffset);
        var desiredCodepoints = steamRecords.Keys
            .Concat(requestedCodepoints)
            .Distinct()
            .OrderBy(codepoint => codepoint)
            .ToList();
        var desiredSet = new HashSet<ushort>(desiredCodepoints);
        var reservedRecords = new HashSet<int>();
        foreach (ushort codepoint in desiredCodepoints)
        {
            List<int> matches;
            if (targetRecords.TryGetValue(codepoint, out matches))
            {
                foreach (int record in matches)
                {
                    reservedRecords.Add(record);
                }
            }
        }

        var donorRecords = new Queue<int>();
        for (int index = 0; index < glyphCount; ++index)
        {
            int record = glyphsOffset + index * 24;
            ushort originalCodepoint = ReadU16(inf, record);
            if (!reservedRecords.Contains(record) &&
                !desiredSet.Contains(originalCodepoint) &&
                originalCodepoint > 0x7F)
            {
                donorRecords.Enqueue(record);
            }
        }

        int neededDonors = desiredCodepoints.Count(codepoint => !targetRecords.ContainsKey(codepoint));
        if (donorRecords.Count < neededDonors)
        {
            throw new InvalidDataException("Suitable donor glyph records were not found.");
        }

        byte[] compressed = File.ReadAllBytes(tg4dPath);
        int visibleCount = 0;
        using (var atlas = new Bitmap(AtlasWidth, AtlasHeight, PixelFormat.Format32bppArgb))
        using (Graphics graphics = Graphics.FromImage(atlas))
        using (var renderFont = new Font(
            family,
            asset.GlyphEmSize,
            FontStyle.Regular,
            GraphicsUnit.Pixel))
        {
            graphics.CompositingMode = CompositingMode.SourceCopy;
            graphics.CompositingQuality = CompositingQuality.HighQuality;
            graphics.InterpolationMode = InterpolationMode.HighQualityBicubic;
            graphics.PixelOffsetMode = PixelOffsetMode.HighQuality;
            graphics.SmoothingMode = SmoothingMode.HighQuality;
            graphics.TextRenderingHint = System.Drawing.Text.TextRenderingHint.AntiAliasGridFit;
            graphics.Clear(Color.Transparent);

            var packer = new AtlasPacker();
            foreach (ushort codepoint in desiredCodepoints)
            {
                List<int> records;
                if (!targetRecords.TryGetValue(codepoint, out records))
                {
                    records = new List<int> { donorRecords.Dequeue() };
                }
                float measuredAdvance = MeasureGlyphAdvance(graphics, renderFont, codepoint);
                ushort advance = checked((ushort)Math.Max(0, Math.Ceiling(measuredAdvance)));
                bool visible = codepoint >= 0x21 &&
                    !Char.IsControl((char)codepoint) &&
                    !Char.IsWhiteSpace((char)codepoint) &&
                    CharUnicodeInfo.GetUnicodeCategory((char)codepoint) != UnicodeCategory.Format;
                Rectangle rectangle = Rectangle.Empty;
                Rectangle logicalBounds = Rectangle.Empty;
                if (visible)
                {
                    using (GraphicsPath path = CreatePositionedGlyphPath(
                        family,
                        codepoint,
                        asset))
                    {
                        logicalBounds = GetGlyphBounds(path, asset, codepoint);
                        rectangle = packer.Allocate(
                            logicalBounds.Width,
                            logicalBounds.Height);
                        DrawGlyph(
                            graphics,
                            path,
                            logicalBounds,
                            rectangle,
                            codepoint);
                    }
                    ++visibleCount;
                }

                foreach (int record in records)
                {
                    WriteU16(inf, record, codepoint);
                    WriteU16(inf, record + 2, visible ? (ushort)logicalBounds.Width : (ushort)0);
                    WriteU16(inf, record + 4, visible ? (ushort)logicalBounds.Height : (ushort)0);
                    WriteU16(inf, record + 6, advance);
                    WriteU16(
                        inf,
                        record + 8,
                        visible ? unchecked((ushort)(short)logicalBounds.Left) : (ushort)0);
                    WriteU16(
                        inf,
                        record + 10,
                        visible ? unchecked((ushort)(short)logicalBounds.Top) : (ushort)0);
                    WriteGlyphRectangle(inf, record, rectangle);
                }
            }

            File.WriteAllBytes(infPath, inf);

            string preview = Path.Combine(
                Path.GetDirectoryName(tg4dPath),
                Path.GetFileNameWithoutExtension(tg4dPath) + ".poc.png");
            atlas.Save(preview, ImageFormat.Png);

            using (var output = new MemoryStream())
            {
                int width = AtlasWidth;
                int height = AtlasHeight;
                for (int level = 0; level < MipCount; ++level)
                {
                    using (Bitmap mip = level == 0
                        ? (Bitmap)atlas.Clone()
                        : ResizeBitmap(atlas, width, height))
                    {
                        byte[] mipRgba = BitmapToRgba(mip);
                        int blockCount = ((width + 3) / 4) * ((height + 3) / 4);
                        byte[] mipBlocks = new byte[blockCount * 16];
                        CompressImage(
                            mipRgba,
                            width,
                            height,
                            mipBlocks,
                            Dxt5 | WeightColourByAlpha | ColourIterativeClusterFit,
                            null);
                        output.Write(mipBlocks, 0, mipBlocks.Length);
                    }

                    width = Math.Max(1, width / 2);
                    height = Math.Max(1, height / 2);
                }

                byte[] result = output.ToArray();
                if (result.Length != compressed.Length)
                {
                    throw new InvalidDataException(
                        "Unexpected TG4D mip-chain size: " + result.Length + " vs " + compressed.Length);
                }
                File.WriteAllBytes(tg4dPath, result);

                byte[] verifiedRgba = new byte[AtlasWidth * AtlasHeight * 4];
                DecompressImage(
                    verifiedRgba,
                    AtlasWidth,
                    AtlasHeight,
                    result,
                    Dxt5);
                using (Bitmap verifiedAtlas = RgbaToBitmap(
                    verifiedRgba,
                    AtlasWidth,
                    AtlasHeight))
                {
                    string verifiedPreview = Path.Combine(
                        Path.GetDirectoryName(tg4dPath),
                        Path.GetFileNameWithoutExtension(tg4dPath) + ".dxt5.png");
                    verifiedAtlas.Save(verifiedPreview, ImageFormat.Png);
                }
            }
        }

        Console.WriteLine(
            "Font: {0}, generated {1} {2} glyphs ({3} visible)",
            Path.GetFileName(infPath),
            desiredCodepoints.Count,
            family.Name,
            visibleCount);
    }

    public static int Main(string[] args)
    {
        if (args.Length != 6)
        {
            Console.Error.WriteLine(
                "Usage: BuildPocAssets <translations.csv> <font-unpacked-dir> <steam-font-unpacked-dir> <font-file> <original-lh2> <output-lh2>");
            return 2;
        }

        try
        {
            Dictionary<uint, TranslationEntry> translations = LoadTranslations(args[0]);
            List<ushort> codepoints = CollectHangulCodepoints(translations);
            int missingCount = translations.Values.Count(
                entry => entry.Translation.StartsWith("< 번역 누락 : ", StringComparison.Ordinal));
            Console.WriteLine(
                "Translations: {0} rows, {1} missing placeholders",
                translations.Count,
                missingCount);
            Console.WriteLine(
                "Hangul glyphs ({0}): {1}",
                codepoints.Count,
                new string(codepoints.Select(value => (char)value).ToArray()));

            var russellSquare = new FontAsset(
                    @"FFN\0105_russellsquare32.inf",
                    @"tg4h\0012_russellsquare32.tg4h",
                    @"tg4d\0013_russellsquare32.tg4d",
                    "russellsquare32",
                    32, 32,
                    25.0f);
            var briemAkademi = new FontAsset(
                    @"FFN\0106_briemakademistdsemibold32.inf",
                    @"tg4h\0000_briemakademistdsemibold32.tg4h",
                    @"tg4d\0001_briemakademistdsemibold32.tg4d",
                    "briemakademistdsemibold32",
                    32, 32,
                    25.0f);
            var eurostile = new FontAsset(
                    @"FFN\0108_eurostileltstdbold32.inf",
                    @"tg4h\0006_eurostileltstdbold32.tg4h",
                    @"tg4d\0007_eurostileltstdbold32.tg4d",
                    "eurostileltstdbold32",
                    32, 32,
                    25.0f);
            var rotisSans = new FontAsset(
                    @"FFN\0109_rotissansserif32.inf",
                    @"tg4h\0010_rotissansserif32.tg4h",
                    @"tg4d\0011_rotissansserif32.tg4d",
                    "rotissansserif32",
                    32, 32,
                    25.0f);

            // Database text-log bodies use Rotis Sans Serif rather than the
            // three fonts used by menus and subtitles. The Chinese container
            // only reserves 190 glyph records for Rotis, so Korean body text
            // looked completely blank even though the translated LCH2 entry
            // was present. Give it the same expanded FFN/texture capacity as
            // Russell Square before drawing the shared Nanum Barun Gothic set.
            ExpandFontFromTemplate(args[1], russellSquare, rotisSans);

            var fonts = new[]
            {
                russellSquare,
                briemAkademi,
                eurostile,
                rotisSans,
            };

            using (var privateFonts = new PrivateFontCollection())
            {
                privateFonts.AddFontFile(Path.GetFullPath(args[3]));
                if (privateFonts.Families.Length != 1)
                {
                    throw new InvalidDataException("Expected exactly one font family in: " + args[3]);
                }
                FontFamily family = privateFonts.Families[0];
                Console.WriteLine("Typeface: {0} ({1})", family.Name, Path.GetFileName(args[3]));
                foreach (FontAsset font in fonts)
                {
                    PatchFont(args[1], args[2], font, codepoints, family);
                }
            }

            PatchLh2(args[4], args[5], translations);
            return 0;
        }
        catch (Exception exception)
        {
            Console.Error.WriteLine(exception);
            return 1;
        }
    }
}
