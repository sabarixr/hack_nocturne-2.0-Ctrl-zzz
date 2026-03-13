"use client";

import { gql } from "@apollo/client";
import { useQuery, useMutation } from "@apollo/client/react";
import { useRouter } from "next/navigation";
import { PhoneCall, AlertTriangle, Clock, MapPin, Eye } from "lucide-react";
import clsx from "clsx";

const OPERATOR_CALLS = gql`
  query GetOperatorCalls {
    operatorCalls(includeEnded: false) {
      id
      status
      emergencyType
      latitude
      longitude
      address
      peakUrgencyScore
      startedAt
      callerName
      callerPhone
      hasOperator
    }
  }
`;

const ACCEPT_CALL = gql`
  mutation AcceptCall($callId: ID!) {
    acceptCall(callId: $callId) {
      id
      status
      hasOperator
    }
  }
`;

export default function DashboardPage() {
  const router = useRouter();
  const { data, loading, error, refetch } = useQuery<any>(OPERATOR_CALLS, {
    pollInterval: 2000,
  });

  const [acceptCall, { loading: accepting }] = useMutation(ACCEPT_CALL, {
    onCompleted: (data: any) => {
      router.push(`/call/${data.acceptCall.id}`);
    },
  });

  if (loading && !data) {
    return (
      <div className="min-h-screen flex items-center justify-center">
        <div className="animate-spin rounded-full h-12 w-12 border-b-2 border-blue-600"></div>
      </div>
    );
  }

  if (error) {
    return (
      <div className="min-h-screen flex flex-col items-center justify-center">
        <p className="text-red-600 mb-4">Error loading calls: {error.message}</p>
        <button
          onClick={() => refetch()}
          className="text-blue-600 hover:underline"
        >
          Try Again
        </button>
      </div>
    );
  }

  const calls = data?.operatorCalls || [];
  
  const handleAccept = (callId: string) => {
    acceptCall({ variables: { callId } });
  };

  const handleMonitor = (callId: string) => {
    router.push(`/call/${callId}`);
  };

  return (
    <div className="min-h-screen bg-slate-50 p-8">
      <div className="max-w-6xl mx-auto">
        <div className="flex justify-between items-center mb-8">
          <h1 className="text-3xl font-bold text-slate-900 flex items-center gap-3">
            <PhoneCall className="w-8 h-8 text-blue-600" />
            Operator Dashboard
          </h1>
          <div className="flex gap-4">
            <div className="bg-red-100 text-red-700 px-4 py-2 rounded-full font-medium flex items-center gap-2">
              <span className="w-2 h-2 rounded-full bg-red-600 animate-pulse"></span>
              {calls.filter((c: Record<string, unknown>) => (c.peakUrgencyScore as number) >= 0.75 && !c.hasOperator).length} Critical Waiting
            </div>
          </div>
        </div>

        <div className="bg-amber-50 border-l-4 border-amber-500 p-4 mb-8 rounded-r-lg">
          <p className="text-amber-800 text-sm">
            <span className="font-bold">System Note:</span> Calls with urgency &lt; 0.75 are automatically handled by the Gemini AI assistant. You can monitor them, but focus on Critical calls (&ge; 0.75).
          </p>
        </div>

        {calls.length === 0 ? (
          <div className="bg-white rounded-xl border border-dashed border-slate-300 p-12 text-center text-slate-500">
            No active emergency calls right now.
          </div>
        ) : (
          <div className="grid gap-4">
            {calls.map((call: Record<string, unknown>) => {
              const isCritical = (call.peakUrgencyScore as number) >= 0.75;
              const callId = call.id as string;
              
              return (
                <div
                  key={callId}
                  className={clsx(
                    "bg-white rounded-xl shadow-sm border overflow-hidden transition-all",
                    isCritical && !call.hasOperator
                      ? "border-red-500 shadow-red-100"
                      : "border-slate-200"
                  )}
                >
                  <div className="p-6 flex items-center justify-between">
                    <div className="flex-1">
                      <div className="flex items-center gap-3 mb-2">
                        {isCritical ? (
                          <span className="bg-red-100 text-red-700 px-2 py-1 rounded text-xs font-bold tracking-wide flex items-center gap-1">
                            <AlertTriangle className="w-3 h-3" />
                            CRITICAL
                          </span>
                        ) : (
                          <span className="bg-amber-100 text-amber-700 px-2 py-1 rounded text-xs font-bold tracking-wide">
                            AI HANDLED
                          </span>
                        )}
                        <span className="text-sm font-semibold text-slate-500 uppercase tracking-wide">
                          {call.emergencyType as string}
                        </span>
                        <span className={clsx(
                          "text-sm font-medium px-2 py-0.5 rounded-full",
                          call.status === "EMERGENCY_TRIGGERED" ? "bg-red-50 text-red-600" :
                          call.status === "ACTIVE" ? "bg-blue-50 text-blue-600" :
                          "bg-slate-100 text-slate-600"
                        )}>
                          {call.status as string}
                        </span>
                      </div>
                      
                      <h3 className="text-xl font-bold text-slate-900 mb-1">
                        {call.callerName as string} <span className="text-slate-500 font-normal text-base ml-2">{call.callerPhone as string}</span>
                      </h3>
                      
                      <div className="flex items-center gap-6 text-sm text-slate-500">
                        <span className="flex items-center gap-1">
                          <MapPin className="w-4 h-4" />
                          {(call.address as string) || "Location unavailable"}
                        </span>
                        <span className="flex items-center gap-1">
                          <Clock className="w-4 h-4" />
                          {new Date(call.startedAt as string).toLocaleTimeString()}
                        </span>
                        <span className="flex items-center gap-1 font-mono">
                          Score: {((call.peakUrgencyScore as number) * 100).toFixed(0)}%
                        </span>
                      </div>
                    </div>

                    <div className="flex flex-col items-end gap-2 ml-6">
                      {call.hasOperator ? (
                        <div className="flex items-center gap-3">
                          <span className="text-sm text-green-600 font-medium flex items-center gap-1">
                            <span className="w-2 h-2 rounded-full bg-green-500"></span>
                            Being handled
                          </span>
                          <button
                            onClick={() => handleMonitor(callId)}
                            className="bg-slate-100 hover:bg-slate-200 text-slate-700 px-4 py-2 rounded-lg font-medium transition-colors flex items-center gap-2"
                          >
                            <Eye className="w-4 h-4" />
                            View
                          </button>
                        </div>
                      ) : isCritical ? (
                        <button
                          onClick={() => handleAccept(callId)}
                          disabled={accepting}
                          className="bg-red-600 hover:bg-red-700 text-white px-8 py-3 rounded-lg font-bold shadow-md shadow-red-200 transition-colors animate-pulse hover:animate-none"
                        >
                          ACCEPT CALL
                        </button>
                      ) : (
                        <button
                          onClick={() => handleMonitor(callId)}
                          className="bg-white border border-slate-300 hover:bg-slate-50 text-slate-700 px-6 py-2 rounded-lg font-medium transition-colors flex items-center gap-2"
                        >
                          <Eye className="w-4 h-4" />
                          Monitor AI
                        </button>
                      )}
                    </div>
                  </div>
                </div>
              );
            })}
          </div>
        )}
      </div>
    </div>
  );
}