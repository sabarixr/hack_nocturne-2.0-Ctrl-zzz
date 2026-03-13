"use client";

import React, { createContext, useContext, useState, useEffect } from "react";
import { useRouter } from "next/navigation";

interface AuthContextType {
  token: string | null;
  setToken: (token: string | null) => void;
  logout: () => void;
}

const AuthContext = createContext<AuthContextType>({
  token: null,
  setToken: () => {},
  logout: () => {},
});

export function AuthProvider({ children }: { children: React.ReactNode }) {
  const [token, setTokenState] = useState<string | null>(null);
  const [isLoaded, setIsLoaded] = useState(false);
  const router = useRouter();

  useEffect(() => {
    let mounted = true;
    const initAuth = () => {
      const savedToken = localStorage.getItem("operator_token");
      if (mounted) {
        if (savedToken) setTokenState(savedToken);
        setIsLoaded(true);
      }
    };
    initAuth();
    return () => { mounted = false; };
  }, []);

  const setToken = (newToken: string | null) => {
    setTokenState(newToken);
    if (newToken) {
      localStorage.setItem("operator_token", newToken);
    } else {
      localStorage.removeItem("operator_token");
    }
  };

  const logout = () => {
    setToken(null);
    router.push("/login");
  };

  if (!isLoaded) return null;

  return (
    <AuthContext.Provider value={{ token, setToken, logout }}>
      {children}
    </AuthContext.Provider>
  );
}

export const useAuth = () => useContext(AuthContext);