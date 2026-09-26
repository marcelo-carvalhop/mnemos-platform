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
