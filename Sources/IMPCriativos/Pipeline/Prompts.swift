import Foundation

/// Instruções enviadas às IAs. Em inglês porque os modelos seguem melhor,
/// mas sempre exigindo que o texto em português seja mantido exatamente.
/// Todas começam pelo contexto do nicho (`Niche`): o app é só para criativos de cassino e bet.
enum Prompts {
    /// Bloco com os termos que não podem aparecer de jeito nenhum.
    static func forbiddenBlock(_ terms: [String], context: String) -> String {
        guard !terms.isEmpty else { return "" }
        let list = terms.map { "\"\($0)\"" }.joined(separator: ", ")
        return """


        FORBIDDEN TERMS — these must NOT appear anywhere in the \(context), in any size, font, language or capitalization, \
        not even partially, blurred or inside phone screens, game thumbnails, signs or logos: \(list).
        """
    }

    /// 1.0.0-beta.7: limpeza guiada pelo plano da IA de planejamento.
    static func cleanFromPlan(_ plan: CreativePlan, extra: String, redoNote: String?) -> String {
        var p = """
        \(Niche.promptContext)

        Edit this advertising image following these exact instructions:
        \(plan.cleanInstruction)
        """
        if !plan.finalText.isEmpty {
            p += """


            After the edit, the image must contain exactly this text (Brazilian Portuguese), character by character, \
            keeping the original typography, colors, effects and position of each line. Do not add any other text:
            <<<
            \(plan.finalText)
            >>>
            """
        }
        p += forbiddenBlock(plan.forbiddenTerms, context: "result")
        p += """


        Fill every erased area naturally so it blends with the surrounding background, as if those elements never existed. \
        Keep everything that the instructions do not mention exactly as it is. Do not add any new logo, watermark, brand \
        name, handle, phone number or website. Keep any 3D character or mascot exactly as it is.
        \(Niche.mandatoryNotices)
        """
        if !extra.trimmed.isEmpty {
            p += "\n\nAdditional instructions from the user (Brazilian Portuguese): \(extra.trimmed)"
        }
        if let note = redoNote, !note.isEmpty {
            p += "\n\nThe previous attempt was rejected. Fix this (Brazilian Portuguese): \(note)"
        }
        return p
    }

    static func clean(removeItems: [String], extra: String, textChanges: String = "", forbidden: [String] = [], redoNote: String?) -> String {
        let list = removeItems.map { "- \($0)" }.joined(separator: "\n")
        var p = """
        \(Niche.promptContext)

        Edit this advertising image. Completely remove ALL of the following brand-identifying elements:
        \(list)

        Fill every removed area naturally so it blends with the surrounding background, as if those elements never existed.
        Do NOT change anything else: keep every other element, the main subject (game, symbols, characters, phone screen, \
        people, sports elements), colors, layout, composition \
        and all other text exactly as they are (except the forbidden terms below, which must disappear even from headlines; \
        rewrite the affected line minimally so it still reads naturally, without adding another brand). \
        Do not add any new logo, watermark, brand name, handle, phone number or website. \
        Keep any 3D character or mascot exactly as it is (same design, pose, colors and render style).
        \(Niche.mandatoryNotices)
        """
        p += forbiddenBlock(forbidden, context: "result")
        if !extra.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            p += "\n\nAdditional instructions from the user (Brazilian Portuguese): \(extra)"
        }
        if !textChanges.trimmed.isEmpty {
            p += """


            After removing the elements above, apply ONLY these changes to the text of the image, requested by the user \
            (Brazilian Portuguese). Write any new words exactly as quoted, with correct accents, in a style that matches \
            the existing typography. This is the only text you may add or change:
            \(textChanges.trimmed)
            """
        }
        if let note = redoNote, !note.isEmpty {
            p += "\n\nThe previous attempt was rejected. Fix this (Brazilian Portuguese): \(note)"
        }
        return p
    }

    static func analysis(removeItems: [String], textChanges: String = "", forbidden: [String] = []) -> String {
        var items = removeItems.map { "- \($0)" }
        items += forbidden.map { "- the word/term \"\($0)\" written anywhere" }
        let list = items.joined(separator: "\n")
        let changes = textChanges.trimmed
        if !changes.isEmpty {
            return """
            \(Niche.promptContext)
            You are a quality checker for advertising images.
            1) This image must NOT contain any of these brand-identifying elements:
            \(list)
            Check carefully whether any trace of them remains (partial logos, leftover letters, faded watermarks).
            2) Transcribe ALL visible text in the image exactly as written (Brazilian Portuguese), preserving accents, \
            capitalization, numbers and line breaks. Do not translate or fix anything.
            3) The user requested these text changes (Brazilian Portuguese):
            \(changes)
            Write the FINAL text the image should have: the transcription from step 2 with these changes applied \
            (if they are already present, it is identical to the transcription). Say whether the image already shows them.

            Respond ONLY with JSON in this exact shape:
            {"clean": true or false, "found": ["short description of each leftover element"], "text": "full transcription", \
            "final_text": "text with the requested changes applied", "changes_applied": true or false}
            """
        }
        return """
        \(Niche.promptContext)
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

    /// 1.0.0-beta.14: a referência é o briefing de conteúdo (assunto, texto, tema, oferta), não o molde de layout.
    /// Cada eixo é uma direção de arte completa; as regras de coerência do nicho valem para todos.
    static func variation(axis: VariationAxis, transcript: String?, extra: String, direction: String = "", textChanges: String = "",
                          forbidden: [String] = [], rules: String = "", redoNote: String?) -> String {
        var p = """
        \(Niche.promptContext)

        Create a NEW variation of this advertising creative for A/B testing.
        Direction for this variation: \(axis.instruction)

        How to vary: treat the reference as the content brief (main subject, text, theme and offer), not as a layout \
        template. Build a new piece that looks designed from scratch by the same designer: new layout, background, \
        graphic style and lighting, following the direction above. The result must be clearly and substantially \
        different from the reference, with high-quality, professional ad design.
        If the direction does not fit the theme of the reference (for example a casino scene for a sports-betting ad, \
        or a stadium for a casino game), adapt it to the reference's own theme instead of changing the theme.
        \(Niche.mainSubject)
        \(Niche.characterRules)

        \(Niche.coherenceRules)
        - \(Niche.mandatoryNotices)
        - Do not add any logo, brand name, watermark, social media handle, phone number or website \
        (other than words that are part of the required text, when there is one).
        """
        if !direction.trimmed.isEmpty {
            p += """


            Overall direction for every variation of this batch, requested by the user (Brazilian Portuguese). \
            Follow it together with the direction above, and make this variation clearly different from the others:
            \(direction.trimmed)
            """
        }
        if let t = transcript?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty {
            p += """


            The image must contain exactly this text, character by character, in Brazilian Portuguese. You may reposition \
            and restyle it, but never rewrite, translate, shorten or misspell it, and do not add other text:
            <<<
            \(t)
            >>>
            """
        } else if !textChanges.trimmed.isEmpty {
            p += """


            Keep the text of the reference, applying only these changes requested by the user (Brazilian Portuguese). \
            Write any new words exactly as quoted, with correct accents:
            \(textChanges.trimmed)
            """
        } else {
            p += "\n\nThe reference has no text. Do not add any text."
        }
        if !rules.trimmed.isEmpty {
            p += "\n\nRules for every variation of this creative:\n\(rules.trimmed)"
        }
        p += forbiddenBlock(forbidden, context: "new image, even if they appear in the reference image")
        if !extra.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            p += "\n\nAdditional instructions from the user (Brazilian Portuguese): \(extra)"
        }
        if let note = redoNote, !note.isEmpty {
            p += "\n\nThe previous attempt was rejected. Fix this (Brazilian Portuguese): \(note)"
        }
        return p
    }

    static func textCheck(expected: String, removeItems: [String], forbidden: [String] = []) -> String {
        var items = removeItems.map { "- \($0)" }
        items += forbidden.map { "- the word/term \"\($0)\" written anywhere (headlines, screens, thumbnails, logos)" }
        let list = items.joined(separator: "\n")
        return """
        \(Niche.promptContext)
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
    /// já existente de operador de cassino/apostas autorizado no Brasil, sem criar promessa nova.
    static func neutral(_ prompt: String) -> String {
        """
        Context: this is a routine graphic design task on an existing, already-published advertisement from an online \
        casino and sports-betting operator that is licensed and regulated in Brazil (Lei 14.790/2023), prepared by its \
        marketing agency for adults only. The request is purely visual (removing brand elements, layout and style \
        changes). Do not add new claims, prizes, odds, bonuses or promises; keep any existing offer text exactly as it is, \
        and keep the mandatory notices ("Ministério da Fazenda adverte", 18+, responsible gambling).

        \(prompt)
        """
    }
}
