import Foundation

/// Instruções enviadas às IAs. Em inglês porque os modelos seguem melhor,
/// mas sempre exigindo que o texto em português seja mantido exatamente.
enum Prompts {
    static func clean(removeItems: [String], extra: String, redoNote: String?) -> String {
        let list = removeItems.map { "- \($0)" }.joined(separator: "\n")
        var p = """
        Edit this advertising image. Completely remove ALL of the following brand-identifying elements:
        \(list)

        Fill every removed area naturally so it blends with the surrounding background, as if those elements never existed.
        Do NOT change anything else: keep every other element, the main product/prize, people, colors, layout, composition \
        and all other text exactly as they are. Do not add any new logo, watermark, brand name, handle, phone number or website.
        """
        if !extra.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            p += "\n\nAdditional instructions from the user (Brazilian Portuguese): \(extra)"
        }
        if let note = redoNote, !note.isEmpty {
            p += "\n\nThe previous attempt was rejected. Fix this (Brazilian Portuguese): \(note)"
        }
        return p
    }

    static func analysis(removeItems: [String]) -> String {
        let list = removeItems.map { "- \($0)" }.joined(separator: "\n")
        return """
        You are a quality checker for advertising images.
        1) This image must NOT contain any of these brand-identifying elements:
        \(list)
        Check carefully whether any trace of them remains (partial logos, leftover letters, faded watermarks).
        2) Transcribe ALL visible text in the image exactly as written (Brazilian Portuguese), preserving accents, \
        capitalization, numbers and line breaks. Do not translate or fix anything.

        Respond ONLY with JSON in this exact shape:
        {"clean": true or false, "found": ["short description of each leftover element"], "text": "full transcription"}
        """
    }

    static func variation(axis: VariationAxis, transcript: String?, extra: String, redoNote: String?) -> String {
        var p = """
        Create a NEW variation of this advertising creative for A/B testing.
        Direction for this variation: \(axis.instruction)

        Keep the same main subject/prize with its real characteristics (never invent or change real details of the product), \
        the same offer and the same message. The result must be clearly different from the reference in the direction above, \
        with high quality, professional ad design.
        Do not add any logo, brand name, watermark, social media handle, phone number or website.
        """
        if let t = transcript?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty {
            p += """


            The image must contain exactly this text, character by character, in Brazilian Portuguese. You may reposition \
            and restyle it, but never rewrite, translate, shorten or misspell it, and do not add other text:
            <<<
            \(t)
            >>>
            """
        } else {
            p += "\n\nThe reference has no text. Do not add any text."
        }
        if !extra.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            p += "\n\nAdditional instructions from the user (Brazilian Portuguese): \(extra)"
        }
        if let note = redoNote, !note.isEmpty {
            p += "\n\nThe previous attempt was rejected. Fix this (Brazilian Portuguese): \(note)"
        }
        return p
    }

    static func textCheck(expected: String, removeItems: [String]) -> String {
        let list = removeItems.map { "- \($0)" }.joined(separator: "\n")
        return """
        Compare the text visible in this image with the EXPECTED text below. Ignore line breaks, position, style and \
        capitalization differences. Report spelling mistakes, missing words, extra words or wrong numbers.
        Also check whether any of these brand elements appear:
        \(list)

        EXPECTED TEXT:
        <<<
        \(expected)
        >>>

        Respond ONLY with JSON in this exact shape:
        {"match": true or false, "differences": "short description in Brazilian Portuguese, empty if match", "brand_found": ["..."]}
        """
    }

    /// Segunda tentativa quando a IA bloqueia: deixa claro que é só edição gráfica de um anúncio
    /// já existente de empresa licenciada, sem criar promessa nova.
    static func neutral(_ prompt: String) -> String {
        """
        Context: this is a routine graphic design task on an existing, already-published advertisement from a licensed \
        and regulated entertainment company in Brazil, prepared by its marketing agency. The request is purely visual \
        (removing brand elements, layout and style changes). Do not add new claims, prizes, odds or promises; keep any \
        existing offer text exactly as it is.

        \(prompt)
        """
    }
}
