#include "cards.h"

size_t loadDefaultCards(CardDefinition* cards, size_t maxCards) {
    static const char* questions[] = {
        "Qual e a funcao principal da camada de enlace?",
        "Qual e a funcao principal do protocolo IP?",
        "Qual e a diferenca fundamental entre TCP e UDP?",
        "O que ocorre no three-way handshake do TCP?",
        "Para que serve o DNS?",
        "Qual e a funcao de uma mascara de sub-rede?",
        "O que faz um roteador?",
        "O que e ARP em redes IPv4?",
        "Qual e a finalidade do DHCP?",
        "O que significa NAT?",
    };
    static const char* answers[] = {
        "Entregar quadros entre nos diretamente conectados ao mesmo enlace e tratar o acesso ao meio fisico.",
        "Enderecar e encaminhar datagramas entre redes, oferecendo entrega por melhor esforco.",
        "TCP oferece fluxo orientado a conexao, confiavel e ordenado; UDP oferece datagramas sem conexao e sem garantias de entrega ou ordem.",
        "Cliente e servidor trocam SYN, SYN-ACK e ACK para sincronizar numeros de sequencia e estabelecer a conexao.",
        "Resolver nomes de dominio em dados como enderecos IP por meio de uma hierarquia distribuida de servidores.",
        "Separar os bits de rede e de host de um endereco IP, permitindo determinar quais enderecos pertencem a mesma sub-rede.",
        "Encaminha pacotes entre redes distintas com base em sua tabela de roteamento e no endereco IP de destino.",
        "E o protocolo usado em uma rede local para descobrir o endereco MAC associado a um endereco IPv4 conhecido.",
        "Fornecer automaticamente parametros como endereco IP, mascara, gateway e servidores DNS.",
        "Network Address Translation: traducao de enderecos entre dominios de rede, frequentemente usada para compartilhar um endereco publico entre hosts privados.",
    };

    const size_t available = sizeof(questions) / sizeof(questions[0]);
    const size_t count = available < maxCards ? available : maxCards;
    for (size_t i = 0; i < count; ++i) {
        cards[i].id = String("demo-redes-") + String(i + 1);
        cards[i].deckId = "demo-redes";
        cards[i].deck = "Redes de Computadores";
        cards[i].type = "basic";
        cards[i].format = "plain";
        cards[i].question = questions[i];
        cards[i].answer = answers[i];
        cards[i].revision = 1;
    }
    return count;
}
