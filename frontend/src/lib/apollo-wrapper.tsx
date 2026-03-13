"use client";

import { ApolloClient, InMemoryCache, HttpLink, split } from "@apollo/client";
import { ApolloProvider } from "@apollo/client/react";
import { setContext } from "@apollo/client/link/context";
import { GraphQLWsLink } from "@apollo/client/link/subscriptions";
import { createClient } from "graphql-ws";
import { getMainDefinition } from "@apollo/client/utilities";
import { useAuth } from "./auth-context";
import { useMemo } from "react";

export function ApolloWrapper({ children }: { children: React.ReactNode }) {
  const { token } = useAuth();

  const client = useMemo(() => {
    const httpLink = new HttpLink({
      uri: "http://localhost:8000/graphql",
    });

    const authLink = setContext((_, { headers }) => {
      return {
        headers: {
          ...headers,
          authorization: token ? `Bearer ${token}` : "",
        },
      };
    });

    let splitLink = authLink.concat(httpLink);

    if (typeof window !== "undefined") {
      const wsLink = new GraphQLWsLink(
        createClient({
          url: "ws://localhost:8000/graphql",
          connectionParams: {
            Authorization: token ? `Bearer ${token}` : "",
          },
        })
      );

      splitLink = split(
        ({ query }) => {
          const definition = getMainDefinition(query);
          return (
            definition.kind === "OperationDefinition" &&
            definition.operation === "subscription"
          );
        },
        wsLink,
        authLink.concat(httpLink)
      );
    }

    return new ApolloClient({
      link: splitLink,
      cache: new InMemoryCache(),
    });
  }, [token]);

  return <ApolloProvider client={client}>{children}</ApolloProvider>;
}