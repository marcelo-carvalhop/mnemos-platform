#include "cards.h"

size_t loadDefaultCards(CardDefinition* cards, size_t maxCards) {
    const size_t count = maxCards < 10 ? maxCards : 10;
    if (count == 0) return 0;

    for (size_t i = 0; i < count; ++i) {
        cards[i] = CardDefinition{};
        cards[i].id = String("demo-redes-") + String(i + 1);
        cards[i].deckId = "demo-redes";
        cards[i].deck = "Redes de Computadores";
        cards[i].format = "plain";
        cards[i].revision = 2;
    }

    if (count > 0) {
        cards[0].type = "open_recall";
        cards[0].question = "Qual e a funcao principal da camada de enlace?";
        cards[0].answer = "Entregar quadros entre nos diretamente conectados ao mesmo enlace e controlar o acesso ao meio.";
    }
    if (count > 1) {
        cards[1].type = "multiple_choice";
        cards[1].question = "Qual protocolo resolve nomes de dominio em enderecos IP?";
        cards[1].options[0] = "ARP";
        cards[1].options[1] = "DNS";
        cards[1].options[2] = "DHCP";
        cards[1].options[3] = "ICMP";
        cards[1].optionCount = 4;
        cards[1].correctOptionIndex = 1;
        cards[1].answer = "DNS";
    }
    if (count > 2) {
        cards[2].type = "true_false";
        cards[2].question = "TCP oferece entrega orientada a conexao e ordenada.";
        cards[2].options[0] = "Verdadeiro";
        cards[2].options[1] = "Falso";
        cards[2].optionCount = 2;
        cards[2].correctOptionIndex = 0;
        cards[2].answer = "Verdadeiro";
    }
    if (count > 3) {
        cards[3].type = "cloze";
        cards[3].question = "Complete: o three-way handshake do TCP usa SYN, ____ e ACK.";
        cards[3].answer = "SYN-ACK";
    }
    if (count > 4) {
        cards[4].type = "application";
        cards[4].question = "Um host conhece o IPv4 de outro host na LAN, mas nao o MAC. Qual protocolo deve usar?";
        cards[4].answer = "ARP";
    }
    if (count > 5) {
        cards[5].type = "open_recall";
        cards[5].question = "Qual e a finalidade do DHCP?";
        cards[5].answer = "Fornecer automaticamente parametros de rede como IP, mascara, gateway e DNS.";
    }
    if (count > 6) {
        cards[6].type = "multiple_choice";
        cards[6].question = "Qual equipamento encaminha pacotes entre redes IP distintas?";
        cards[6].options[0] = "Hub";
        cards[6].options[1] = "Roteador";
        cards[6].options[2] = "Repetidor";
        cards[6].options[3] = "Patch panel";
        cards[6].optionCount = 4;
        cards[6].correctOptionIndex = 1;
        cards[6].answer = "Roteador";
    }
    if (count > 7) {
        cards[7].type = "true_false";
        cards[7].question = "UDP garante retransmissao e ordem de entrega.";
        cards[7].options[0] = "Verdadeiro";
        cards[7].options[1] = "Falso";
        cards[7].optionCount = 2;
        cards[7].correctOptionIndex = 1;
        cards[7].answer = "Falso";
    }
    if (count > 8) {
        cards[8].type = "open_recall";
        cards[8].question = "O que significa NAT?";
        cards[8].answer = "Network Address Translation: traducao de enderecos entre dominios de rede.";
    }
    if (count > 9) {
        cards[9].type = "application";
        cards[9].question = "Para saber se 192.168.1.20 e 192.168.1.80 estao na mesma /24, que parte do endereco deve ser comparada?";
        cards[9].answer = "Os 24 bits de rede definidos pela mascara /24; ambos pertencem a 192.168.1.0/24.";
    }

    return count;
}


namespace {

struct MandarinSeedCard {
    const char* hanzi;
    const char* pinyin;
    const char* meaning;
};

constexpr MandarinSeedCard MANDARIN_SEED[] = {
    {"一", "yī", "um"},
    {"二", "èr", "dois"},
    {"三", "sān", "três"},
    {"四", "sì", "quatro"},
    {"五", "wǔ", "cinco"},
    {"六", "liù", "seis"},
    {"七", "qī", "sete"},
    {"八", "bā", "oito"},
    {"九", "jiǔ", "nove"},
    {"十", "shí", "dez"},
    {"百", "bǎi", "cem"},
    {"千", "qiān", "mil"},
    {"人", "rén", "pessoa"},
    {"我", "wǒ", "eu"},
    {"你", "nǐ", "você"},
    {"他", "tā", "ele"},
    {"她", "tā", "ela"},
    {"们", "men", "marca de plural"},
    {"的", "de", "partícula possessiva"},
    {"是", "shì", "ser"},
    {"不", "bù", "não"},
    {"有", "yǒu", "ter"},
    {"在", "zài", "estar; em"},
    {"这", "zhè", "este"},
    {"那", "nà", "aquele"},
    {"哪", "nǎ", "qual"},
    {"谁", "shéi", "quem"},
    {"什", "shén", "que; em shenme"},
    {"么", "me", "partícula; em shénme"},
    {"好", "hǎo", "bom"},
    {"大", "dà", "grande"},
    {"小", "xiǎo", "pequeno"},
    {"多", "duō", "muito"},
    {"少", "shǎo", "pouco"},
    {"中", "zhōng", "meio; China"},
    {"国", "guó", "país"},
    {"家", "jiā", "casa; familia"},
    {"学", "xué", "estudar"},
    {"生", "shēng", "nascer; aluno"},
    {"老", "lǎo", "velho"},
    {"师", "shī", "mestre; professor"},
    {"朋", "péng", "amigo; em pengyou"},
    {"友", "yǒu", "amigo"},
    {"爸", "bà", "pai"},
    {"妈", "mā", "mãe"},
    {"子", "zǐ", "filho; crianca"},
    {"女", "nǚ", "mulher; filha"},
    {"男", "nán", "homem"},
    {"日", "rì", "sol; dia"},
    {"月", "yuè", "lua; mes"},
    {"年", "nián", "ano"},
    {"天", "tiān", "céu; dia"},
    {"今", "jīn", "hoje; atual"},
    {"明", "míng", "claro; amanha"},
    {"时", "shí", "tempo; hora"},
    {"分", "fēn", "minuto; parte"},
    {"上", "shàng", "cima; subir"},
    {"下", "xià", "baixo; descer"},
    {"左", "zuǒ", "esquerda"},
    {"右", "yòu", "direita"},
    {"前", "qián", "frente; antes"},
    {"后", "hòu", "atrás; depois"},
    {"里", "lǐ", "dentro"},
    {"外", "wài", "fora"},
    {"东", "dōng", "leste"},
    {"西", "xī", "oeste"},
    {"南", "nán", "sul"},
    {"北", "běi", "norte"},
    {"来", "lái", "vir"},
    {"去", "qù", "ir"},
    {"回", "huí", "voltar"},
    {"看", "kàn", "ver; olhar"},
    {"听", "tīng", "ouvir"},
    {"说", "shuō", "falar"},
    {"读", "dú", "ler"},
    {"写", "xiě", "escrever"},
    {"吃", "chī", "comer"},
    {"喝", "hē", "beber"},
    {"买", "mǎi", "comprar"},
    {"卖", "mài", "vender"},
    {"做", "zuò", "fazer"},
    {"开", "kāi", "abrir; dirigir"},
    {"关", "guān", "fechar"},
    {"想", "xiǎng", "pensar; querer"},
    {"要", "yào", "querer; precisar"},
    {"会", "huì", "saber; poder"},
    {"能", "néng", "poder; capacidade"},
    {"给", "gěi", "dar"},
    {"问", "wèn", "perguntar"},
    {"答", "dá", "responder"},
    {"爱", "ài", "amar"},
    {"喜", "xǐ", "gostar; alegria"},
    {"欢", "huān", "alegria; em xihuan"},
    {"水", "shuǐ", "água"},
    {"火", "huǒ", "fogo"},
    {"木", "mù", "madeira"},
    {"山", "shān", "montanha"},
    {"口", "kǒu", "boca"},
    {"手", "shǒu", "mão"},
    {"心", "xīn", "coração"},
};

constexpr size_t MANDARIN_SEED_COUNT =
    sizeof(MANDARIN_SEED) / sizeof(MANDARIN_SEED[0]);

}  // namespace

size_t appendMandarinTrainingDeck(CardDefinition* cards,
                                  CardState* states,
                                  size_t maxCards,
                                  size_t count) {
    for (size_t i = 0; i < count; ++i) {
        if (cards[i].deckId == "training-mandarin-100") {
            return count;
        }
    }

    if (maxCards < count ||
        maxCards - count < MANDARIN_SEED_COUNT) {
        Serial.printf(
            "[cards] deck mandarim nao inserido: capacidade %u/%u\n",
            static_cast<unsigned>(count),
            static_cast<unsigned>(maxCards));
        return count;
    }

    const size_t initialCount = count;

    for (size_t i = 0; i < MANDARIN_SEED_COUNT; ++i) {
        CardDefinition& card = cards[count];
        CardState& state = states[count];

        card = CardDefinition{};
        state = CardState{};

        char id[40];
        snprintf(id, sizeof(id), "training-mandarin-%03u",
                 static_cast<unsigned>(i + 1));

        card.id = id;
        card.deckId = "training-mandarin-100";
        card.deck = "Mandarim - 100 caracteres";
        card.type = "open_recall";
        card.format = "plain";
        card.question = MANDARIN_SEED[i].hanzi;
        card.answer =
            String(MANDARIN_SEED[i].pinyin) +
            " - " +
            String(MANDARIN_SEED[i].meaning);
        card.revision = 1;

        state.id = card.id;
        ++count;
    }

    Serial.printf(
        "[cards] deck mandarim inserido: %u cartoes\n",
        static_cast<unsigned>(count - initialCount));

    return count;
}


bool refreshMandarinTrainingDeck(
    CardDefinition* cards,
    size_t count) {

    bool changed = false;

    for (size_t i = 0; i < count; ++i) {
        CardDefinition& card = cards[i];

        if (
            card.deckId !=
            "training-mandarin-100"
        ) {
            continue;
        }

        int seedIndex = -1;

        if (
            card.id.startsWith(
                "training-mandarin-")
        ) {
            seedIndex =
                card.id.substring(18).toInt() - 1;
        }

        if (
            seedIndex < 0 ||
            seedIndex >=
                static_cast<int>(
                    MANDARIN_SEED_COUNT)
        ) {
            continue;
        }

        const MandarinSeedCard& seed =
            MANDARIN_SEED[seedIndex];

        const String expectedAnswer =
            String(seed.pinyin) +
            " - " +
            String(seed.meaning);

        if (
            card.question != seed.hanzi ||
            card.answer != expectedAnswer ||
            card.deck !=
                "Mandarim - 100 caracteres"
        ) {
            card.question = seed.hanzi;
            card.answer = expectedAnswer;
            card.deck =
                "Mandarim - 100 caracteres";

            if (card.revision < 2) {
                card.revision = 2;
            }

            changed = true;
        }
    }

    if (changed) {
        Serial.println(
            "[cards] deck mandarim atualizado: "
            "pinyin tonal + portugues acentuado");
    }

    return changed;
}
