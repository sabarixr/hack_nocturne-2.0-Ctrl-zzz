"use client";

import { useState, use } from "react";
import { gql } from "@apollo/client";
import { useQuery, useMutation, useSubscription } from "@apollo/client/react";
import { useRouter } from "next/navigation";
import { ArrowLeft, Send, Siren, MapPin, Activity, AlertCircle } from "lucide-react";
import clsx from "clsx";

const CALL_DETAIL = gql`
  query GetCallDetail($callId: ID!) {
    operatorCallDetail(callId: $callId) {
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
    callFrames(callId: $callId) {
      id
      recognizedSigns
      urgencyScore
      recordedAt
    }
  }
`;

const CALL_SUB = gql`
  subscription OnCallUpdate($callId: ID!) {
    emergencyCallUpdated(callId: $callId) {
      callId
      status
      peakUrgencyScore
      emergencyType
      updatedAt
    }
  }
`;

const MSG_SUB = gql`
  subscription OnMsg($callId: ID!) {
    operatorMessageReceived(callId: $callId) {
      messageId
      text
      sentAt
    }
  }
`;

const SEND_MSG = gql`
  mutation SendMsg($callId: ID!, $text: String!) {
    sendOperatorMessage(input: { callId: $callId, text: $text }) {
      id
      sentAt
    }
  }
`;

const DISPATCH = gql`
  mutation Dispatch($callId: ID!, $type: String!) {
    createDispatchEvent(input: { callId: $callId, dispatchType: $type }) {
      id
      dispatchType
    }
  }
`;

export default function CallHandlingPage({ params }: { params: Promise<{ id: string }> }) {
  const router = useRouter();
  const { id } = use(params);
  const [msgText, setMsgText] = useState("");
  const [messages, setMessages] = useState<Record<string, unknown>[]>([]);

  const { data, loading } = useQuery<any>(CALL_DETAIL, {
    variables: { callId: id },
    pollInterval: 5000,
  });

  useSubscription(CALL_SUB, { variables: { callId: id } });

  useSubscription(MSG_SUB, {
    variables: { callId: id },
    onData: ({ data: subData }: { data: any }) => {
      const newMsg = subData.data.operatorMessageReceived;
      setMessages((prev) => [...prev, newMsg]);
    },
  });

  const [sendMsg, { loading: sending }] = useMutation(SEND_MSG);
  const [dispatchEvent] = useMutation(DISPATCH);

  const handleSend = (e: React.FormEvent) => {
    e.preventDefault();
    if (!msgText.trim()) return;
    sendMsg({ variables: { callId: id, text: msgText } });
    setMsgText("");
  };

  if (loading && !data) return <div className="p-8">Loading...</div>;
  if (!data?.operatorCallDetail) return <div className="p-8">Call not found</div>;

  const call = data.operatorCallDetail;
  const frames = data.callFrames || [];
  
  // Aggregate recent signs
  const allSigns = frames.flatMap((f: Record<string, unknown>) => f.recognizedSigns as string[]).slice(-20);

  return (
    <div className="min-h-screen bg-slate-100 flex flex-col">
      <div className="bg-white border-b px-6 py-4 flex items-center justify-between shadow-sm z-10 relative">
        <div className="flex items-center gap-4">
          <button onClick={() => router.push("/dashboard")} className="p-2 hover:bg-slate-100 rounded-full transition-colors">
            <ArrowLeft className="w-5 h-5" />
          </button>
          <div>
            <h1 className="text-xl font-bold text-slate-900 flex items-center gap-2">
              {call.callerName}
              <span className={clsx(
                "text-xs px-2 py-1 rounded-full ml-2 uppercase font-bold",
                call.peakUrgencyScore >= 0.75 ? "bg-red-100 text-red-700" : "bg-blue-100 text-blue-700"
              )}>
                {call.emergencyType}
              </span>
            </h1>
            <p className="text-sm text-slate-500">{call.callerPhone}</p>
          </div>
        </div>
        <div className="flex gap-3">
          <button onClick={() => dispatchEvent({ variables: { callId: id, type: "AMBULANCE" } })} className="bg-amber-100 hover:bg-amber-200 text-amber-800 px-4 py-2 rounded-lg font-bold flex items-center gap-2 transition-colors">
            <Siren className="w-4 h-4" /> Dispatch Ambulance
          </button>
          <button onClick={() => dispatchEvent({ variables: { callId: id, type: "POLICE" } })} className="bg-blue-100 hover:bg-blue-200 text-blue-800 px-4 py-2 rounded-lg font-bold flex items-center gap-2 transition-colors">
            <Siren className="w-4 h-4" /> Dispatch Police
          </button>
        </div>
      </div>

      <div className="flex-1 flex overflow-hidden">
        {/* Left Column: Context */}
        <div className="w-1/3 border-r bg-white overflow-y-auto p-6 flex flex-col gap-6">
          <div className="bg-slate-50 p-4 rounded-xl border border-slate-200">
            <h3 className="text-sm font-bold text-slate-500 uppercase tracking-wide flex items-center gap-2 mb-3">
              <Activity className="w-4 h-4" /> Live Status
            </h3>
            <div className="space-y-4">
              <div>
                <div className="flex justify-between text-sm mb-1">
                  <span className="font-medium">Urgency Level</span>
                  <span className="font-mono">{(call.peakUrgencyScore * 100).toFixed(0)}%</span>
                </div>
                <div className="h-2 bg-slate-200 rounded-full overflow-hidden">
                  <div 
                    className={clsx("h-full", call.peakUrgencyScore >= 0.75 ? "bg-red-500" : "bg-blue-500")}
                    style={{ width: `${call.peakUrgencyScore * 100}%` }}
                  />
                </div>
              </div>
              <div className="flex items-start gap-2 text-sm text-slate-700">
                <MapPin className="w-4 h-4 text-slate-400 shrink-0 mt-0.5" />
                <p>{call.address || "Location tracking active..."}</p>
              </div>
            </div>
          </div>

          <div className="flex-1 border rounded-xl overflow-hidden flex flex-col">
            <div className="bg-slate-50 p-3 border-b border-slate-200">
              <h3 className="text-sm font-bold text-slate-500 uppercase tracking-wide flex items-center gap-2">
                <AlertCircle className="w-4 h-4" /> Recognized Signs
              </h3>
            </div>
            <div className="p-4 flex-1 overflow-y-auto bg-white flex flex-wrap content-start gap-2">
              {allSigns.length === 0 ? (
                <p className="text-slate-400 text-sm text-center w-full py-4">No signs detected yet.</p>
              ) : (
                allSigns.map((sign: string, i: number) => (
                  <span key={i} className="bg-slate-100 border border-slate-200 text-slate-700 px-3 py-1.5 rounded-lg text-sm font-medium">
                    {sign}
                  </span>
                ))
              )}
            </div>
          </div>
        </div>

        {/* Right Column: Chat */}
        <div className="flex-1 flex flex-col bg-slate-50">
          <div className="flex-1 overflow-y-auto p-6 space-y-4">
            <div className="text-center">
              <span className="bg-slate-200 text-slate-600 text-xs px-3 py-1 rounded-full font-medium">
                Call started {new Date(call.startedAt).toLocaleTimeString()}
              </span>
            </div>
            
            {messages.map((m, i) => (
              <div key={i} className="flex flex-col items-end">
                <div className="bg-blue-600 text-white rounded-2xl rounded-tr-sm px-5 py-3 max-w-[80%] shadow-sm">
                  {m.text as string}
                </div>
                <span className="text-xs text-slate-400 mt-1 mr-1">
                  {new Date(m.sentAt as string).toLocaleTimeString()}
                </span>
              </div>
            ))}
          </div>
          
          <div className="p-4 bg-white border-t border-slate-200">
            <form onSubmit={handleSend} className="flex gap-3">
              <input
                type="text"
                value={msgText}
                onChange={(e) => setMsgText(e.target.value)}
                placeholder="Type message to convert to sign language avatar..."
                className="flex-1 border border-slate-300 rounded-full px-5 py-3 outline-none focus:ring-2 focus:ring-blue-500 focus:border-blue-500"
              />
              <button 
                type="submit" 
                disabled={sending || !msgText.trim()}
                className="bg-blue-600 hover:bg-blue-700 disabled:opacity-50 text-white w-12 h-12 rounded-full flex items-center justify-center transition-colors shadow-sm"
              >
                <Send className="w-5 h-5 ml-1" />
              </button>
            </form>
          </div>
        </div>
      </div>
    </div>
  );
}