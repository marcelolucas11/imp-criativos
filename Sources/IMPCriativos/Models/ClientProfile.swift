import Foundation

/// Um eixo de variação: a "direção" que diferencia uma variação das outras.
struct VariationAxis: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var instruction: String
}

/// Perfil de um cliente: o que remover, como variar e instruções extras.
/// Fica salvo só no Mac do usuário (Application Support), nunca no repositório.
struct ClientProfile: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var removeItems: [String]
    var axes: [VariationAxis]
    var defaultVariations: Int
    var extraInstructions: String
    var createdAt = Date()
    /// 1.0.0-beta.6: instruções de lote salvas para reaproveitar (opcional para abrir perfis antigos).
    var savedInstructions: [String]?

    static let defaultRemoveItems: [String] = [
        "Logotipo da empresa",
        "Nome da empresa (escrito em qualquer lugar da imagem)",
        "@ de Instagram ou outras redes sociais",
        "Site / endereço de internet",
        "Telefone ou WhatsApp",
        "CNPJ",
        "Marca d'água ou selo da empresa",
    ]

    static let defaultAxes: [VariationAxis] = [
        VariationAxis(name: "Fundo e paleta",
                      instruction: "Replace the background and the color palette with a fresh, vibrant combination. Keep high contrast and perfect legibility."),
        VariationAxis(name: "Composição",
                      instruction: "Rearrange the composition: change the position and scale of the main subject (the prize/product) and of the text block."),
        VariationAxis(name: "Iluminação e clima",
                      instruction: "Change the lighting and mood (for example: night scene with neon lights, golden sunset, or a clean studio look)."),
        VariationAxis(name: "Ângulo do prêmio",
                      instruction: "Show the main subject from a different angle or perspective, without changing any of its real characteristics."),
        VariationAxis(name: "Estilo gráfico",
                      instruction: "Apply a different ad graphic style (for example: 3D elements, geometric shapes, glow effects), keeping it professional and premium."),
        VariationAxis(name: "Cenário",
                      instruction: "Place the main subject in a different setting or environment that is coherent with the theme of the ad."),
    ]

    static func newProfile(named name: String = "Novo cliente") -> ClientProfile {
        ClientProfile(name: name,
                      removeItems: defaultRemoveItems,
                      axes: defaultAxes,
                      defaultVariations: 4,
                      extraInstructions: "")
    }

    static var example: ClientProfile {
        var p = newProfile(named: "Exemplo")
        p.extraInstructions = "Troque pelos nomes reais: ex. remover o nome \"Minha Empresa Prêmios\" e o @minhaempresa."
        return p
    }
}
